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
    var progress: AnalysisProgress?
    var statusMessage: String?
    var isActive: Bool = false
    
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
    
    func onAppear() {
        isActive = true
        if groups.isEmpty && !isScanning {
            startScan()
        }
    }
    
    func onDisappear() {
        isActive = false
        cancel()
    }
    
    var totalSavingsBytes: Int64 {
        groups.reduce(0) { $0 + $1.savingsBytes }
    }
    
    var totalRedundantCount: Int {
        groups.reduce(0) { $0 + $1.nonKeepers.count }
    }
    
    func startScan() {
        scanTask?.cancel()
        scanTask = Task {
            isScanning = true
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
            }
            self.isScanning = false
            self.progress = nil
            self.statusMessage = nil
        }
    }
    
    func cancel() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
        progress = nil
    }
    
    // MARK: - Keeper Management
    
    func setKeeper(assetId: String, in groupId: String) {
        if let idx = groups.firstIndex(where: { $0.id == groupId }) {
            groups[idx].keeperId = assetId
        }
    }
    
    // MARK: - Deletion Operations
    
    func deleteNonKeepers(in group: AssetGroup) async throws {
        let toDelete = group.nonKeepers.map(\.localIdentifier)
        let deleted = try await PhotoLibraryService.shared.deleteAssets(localIdentifiers: toDelete)
        
        withAnimation(.snappy) {
            if let idx = groups.firstIndex(where: { $0.id == group.id }) {
                groups[idx].assets.removeAll { deleted.contains($0.localIdentifier) }
                if groups[idx].assets.count < 2 {
                    groups.remove(at: idx)
                }
            }
        }
    }
    
    func deleteAllNonKeepers() async throws {
        let allNonKeepers = groups.flatMap { $0.nonKeepers.map(\.localIdentifier) }
        guard !allNonKeepers.isEmpty else { return }
        
        let deleted = try await PhotoLibraryService.shared.deleteAssets(localIdentifiers: allNonKeepers)
        withAnimation(.snappy) {
            for i in groups.indices.reversed() {
                groups[i].assets.removeAll { deleted.contains($0.localIdentifier) }
                if groups[i].assets.count < 2 {
                    groups.remove(at: i)
                }
            }
        }
    }
}
