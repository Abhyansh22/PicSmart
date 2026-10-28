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
    private var cancellables = Set<AnyCancellable>()
    
    init(category: GalleryCategory) {
        self.category = category
    }
    
    func onAppear() {
        isActive = true
    }
    
    func onDisappear() {
        isActive = false
    }
    
    var totalSavingsBytes: Int64 {
        groups.reduce(0) { $0 + $1.savingsBytes }
    }
    
    var totalRedundantCount: Int {
        groups.reduce(0) { $0 + $1.markedForDeletionIds.count }
    }
    
    func executeScan() async {
        let authStatus = PhotoLibraryService.shared.authorizationStatus
        guard authStatus == .authorized || authStatus == .limited else {
            self.isScanning = false
            self.progress = nil
            self.statusMessage = nil
            return
        }
        
        guard !isScanning else { return }
        
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
        
        if Task.isCancelled {
            if !result.isEmpty {
                self.groups = result
            }
            self.hasCompletedScan = false
            self.onScanCompleted?()
        } else {
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
        isScanning = false
        hasCompletedScan = false
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
            
            let explicitMarked = dto.markedForDeletionIds.map { Set($0) }
            hydratedGroups.append(AssetGroup(
                id: dto.id,
                assets: assets,
                keeperId: dto.keeperId ?? assets.first?.localIdentifier,
                bestShotId: dto.bestShotId ?? assets.first?.localIdentifier,
                fileSizes: dto.fileSizes,
                similarityScore: dto.similarityScore,
                markedForDeletionIds: explicitMarked
            ))
        }
        
        if !hydratedGroups.isEmpty {
            self.groups = hydratedGroups
            self.hasCompletedScan = true
            self.onScanCompleted?()
        }
    }
    
    // MARK: - Keeper & Selection Management
    
    func setKeeper(assetId: String, in groupId: String) {
        if let idx = groups.firstIndex(where: { $0.id == groupId }) {
            groups[idx].keeperId = assetId
            // The keeper cannot be marked for deletion
            groups[idx].markedForDeletionIds.remove(assetId)
            Task.detached(priority: .utility) { [cat = self.category, grps = self.groups] in
                try? await PersistentClusterStore.shared.saveClusters(grps, for: cat)
            }
        }
    }
    
    func toggleMarkedForDeletion(assetId: String, in groupId: String) {
        if let idx = groups.firstIndex(where: { $0.id == groupId }) {
            // If it is the current keeper and user wants to mark it for deletion, prompt or reassign keeper
            if groups[idx].markedForDeletionIds.contains(assetId) {
                groups[idx].markedForDeletionIds.remove(assetId)
            } else {
                // If it was keeper, pick another asset as keeper if available
                if groups[idx].keeperId == assetId {
                    let nextKeeper = groups[idx].assets.first { $0.localIdentifier != assetId }?.localIdentifier
                    groups[idx].keeperId = nextKeeper
                }
                groups[idx].markedForDeletionIds.insert(assetId)
            }
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
                groups[i].markedForDeletionIds.subtract(deletedIds)
                if groups[i].assets.count < 2 {
                    groups.remove(at: i)
                }
            }
        }
    }
    
    // MARK: - Deletion Operations
    
    func deleteMarkedAssets(in group: AssetGroup) async throws {
        let toDelete = Array(group.markedForDeletionIds)
        guard !toDelete.isEmpty else { return }
        let deleted = try await PhotoLibraryService.shared.deleteAssets(localIdentifiers: toDelete)
        pruneDeletedAssets(deleted)
    }
    
    func deleteAllMarkedAssets() async throws {
        let allMarked = groups.flatMap { Array($0.markedForDeletionIds) }
        guard !allMarked.isEmpty else { return }
        let deleted = try await PhotoLibraryService.shared.deleteAssets(localIdentifiers: allMarked)
        pruneDeletedAssets(deleted)
    }
}
