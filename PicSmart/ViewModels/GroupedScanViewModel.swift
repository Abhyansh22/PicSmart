//
//  GroupedScanViewModel.swift
//  PicSmart
//

import Photos
import SwiftUI
import Combine
import Observation

@Observable
@MainActor
final class GroupedScanViewModel {
    let category: GalleryCategory
    var groups: [AssetGroup] = []
    var isScanning: Bool = false
    var isRefreshing: Bool = false
    var hasCompletedScan: Bool = false
    var progress: AnalysisProgress?
    var statusMessage: String?
    var isActive: Bool = false
    
    var onScanCompleted: (() -> Void)?
    
    @ObservationIgnored
    private var scanTask: Task<Void, Never>?
    @ObservationIgnored
    private var cancellables = Set<AnyCancellable>()
    
    init(category: GalleryCategory) {
        self.category = category
        
        PhotoLibraryService.shared.libraryChangePublisher
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.isActive else { return }
                self.startScan()
            }
            .store(in: &cancellables)
    }
    
    func startScanIfNeeded() {
        if !isScanning && (!hasCompletedScan || groups.isEmpty) {
            startScan()
        }
    }
    
    func onAppear() {
        isActive = true
    }
    
    func onDisappear() {
        isActive = false
        // Note: We DO NOT cancel the scan task here so that navigating back
        // keeps background scanning alive and doesn't discard user progress.
    }
    
    var totalSavingsBytes: Int64 {
        groups.reduce(0) { $0 + $1.savingsBytes }
    }
    
    var totalRedundantCount: Int {
        groups.reduce(0) { $0 + $1.nonKeepers.count }
    }
    
    func startScan() {
        guard !isScanning else { return }
        scanTask?.cancel()
        scanTask = Task {
            await executeScan()
        }
    }
    
    func executeScan() async {
        let authStatus = PhotoLibraryService.shared.authorizationStatus
        guard authStatus == .authorized || authStatus == .limited else {
            self.isScanning = false
            self.progress = nil
            self.statusMessage = nil
            return
        }
        
        guard !isScanning else {
            while isScanning {
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            return
        }
        
        isScanning = true
        hasCompletedScan = false
        progress = AnalysisProgress(completed: 0, total: 1, stage: "Starting scan…")
        statusMessage = "Analyzing photo library…"
        
        let result: [AssetGroup]
        switch category {
        case .duplicatePhotos:
            result = await MediaAnalyzerEngine.shared.scanDuplicatePhotos { [weak self] prog in
                Task { @MainActor in
                    self?.progress = prog
                    self?.statusMessage = prog.stage
                }
            }
        case .duplicateVideos:
            result = await MediaAnalyzerEngine.shared.scanDuplicateVideos { [weak self] prog in
                Task { @MainActor in
                    self?.progress = prog
                    self?.statusMessage = prog.stage
                }
            }
        case .similarPhotos:
            result = await MediaAnalyzerEngine.shared.scanSimilarPhotos { [weak self] prog in
                Task { @MainActor in
                    self?.progress = prog
                    self?.statusMessage = prog.stage
                }
            }
        default:
            result = []
        }
        
        if !Task.isCancelled {
            self.groups = result
            self.hasCompletedScan = true
            self.onScanCompleted?()
            Task.detached(priority: .utility) { [cat = self.category, res = result] in
                try? await PersistentClusterStore.shared.saveClusters(res, for: cat)
            }
        }
        self.isScanning = false
        self.progress = nil
        self.statusMessage = nil
    }
    
    /// Non-destructive in-place refresh for pull-to-refresh without tearing down current UI tree.
    func refresh() async {
        guard !isScanning && !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        
        let result: [AssetGroup]
        switch category {
        case .duplicatePhotos:
            result = await MediaAnalyzerEngine.shared.scanDuplicatePhotos()
        case .duplicateVideos:
            result = await MediaAnalyzerEngine.shared.scanDuplicateVideos()
        case .similarPhotos:
            result = await MediaAnalyzerEngine.shared.scanSimilarPhotos()
        default:
            result = []
        }
        
        guard !Task.isCancelled else { return }
        withAnimation(.snappy) {
            self.groups = result
            self.hasCompletedScan = true
        }
        self.onScanCompleted?()
        Task.detached(priority: .utility) { [cat = self.category, res = result] in
            try? await PersistentClusterStore.shared.saveClusters(res, for: cat)
        }
    }
    
    func cancel() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
        hasCompletedScan = true
        progress = nil
        statusMessage = nil
    }
    
    // MARK: - Cold Launch Hydration
    
    func hydrate(from dtos: [PersistedGroupDTO]) {
        guard groups.isEmpty && !hasCompletedScan else { return }
        
        let allIds = dtos.flatMap(\.assetIds)
        guard !allIds.isEmpty else { return }
        
        let options = PHFetchOptions()
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: allIds, options: options)
        var assetMap = [String: PHAsset]()
        fetchResult.enumerateObjects { asset, _, _ in
            assetMap[asset.localIdentifier] = asset
        }
        
        var hydratedGroups: [AssetGroup] = []
        for dto in dtos {
            let assets = dto.assetIds.compactMap { assetMap[$0] }
            guard assets.count >= 2 else { continue }
            
            hydratedGroups.append(AssetGroup(
                id: dto.id,
                assets: assets,
                keeperId: dto.keeperId ?? assets.first?.localIdentifier,
                bestShotId: dto.bestShotId ?? assets.first?.localIdentifier,
                fileSizes: dto.fileSizes,
                similarityScore: dto.similarityScore
            ))
        }
        
        if !hydratedGroups.isEmpty {
            self.groups = hydratedGroups
            self.hasCompletedScan = true
            self.onScanCompleted?()
        }
    }
    
    // MARK: - Keeper Management
    
    func setKeeper(assetId: String, in groupId: String) {
        if let idx = groups.firstIndex(where: { $0.id == groupId }) {
            groups[idx].keeperId = assetId
            Task.detached(priority: .utility) { [cat = self.category, grps = self.groups] in
                try? await PersistentClusterStore.shared.saveClusters(grps, for: cat)
            }
        }
    }
    
    // MARK: - In-Memory Pruning
    
    func pruneDeletedAssets(_ deletedIds: Set<String>) {
        withAnimation(.snappy) {
            for i in groups.indices.reversed() {
                groups[i].assets.removeAll { deletedIds.contains($0.localIdentifier) }
                if groups[i].assets.count < 2 {
                    groups.remove(at: i)
                }
            }
        }
    }
    
    // MARK: - Deletion Operations
    
    func deleteNonKeepers(in group: AssetGroup) async throws {
        let toDelete = group.nonKeepers.map(\.localIdentifier)
        let deleted = try await PhotoLibraryService.shared.deleteAssets(localIdentifiers: toDelete)
        pruneDeletedAssets(deleted)
    }
    
    func deleteAllNonKeepers() async throws {
        let allNonKeepers = groups.flatMap { $0.nonKeepers.map(\.localIdentifier) }
        guard !allNonKeepers.isEmpty else { return }
        let deleted = try await PhotoLibraryService.shared.deleteAssets(localIdentifiers: allNonKeepers)
        pruneDeletedAssets(deleted)
    }
}
