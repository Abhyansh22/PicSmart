//
//  MediaCollectionViewModel.swift
//  PicSmart
//

import Photos
import SwiftUI
import Combine
import Observation

@Observable
@MainActor
final class MediaCollectionViewModel {
    let category: GalleryCategory
    
    // For Screenshots and Videos: zero-copy database cursor
    var cursor: FetchResultCollection?
    
    // For Large Videos: pre-sorted array streaming from background engine
    var sortedLargeVideoAssets: [PHAsset] = []
    var fileSizes: [String: Int64] = [:]
    
    var isLoading: Bool = false
    var isRefreshing: Bool = false
    var hasLoaded: Bool = false
    var progressMessage: String?
    var progressFraction: Double = 0.0
    var progress: AnalysisProgress?
    var isActive: Bool = false
    
    var onScanCompleted: (() -> Void)?
    
    @ObservationIgnored
    private var loadTask: Task<Void, Never>?
    @ObservationIgnored
    private var cancellables = Set<AnyCancellable>()
    
    init(category: GalleryCategory) {
        self.category = category
        
        PhotoLibraryService.shared.libraryChangePublisher
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.isActive else { return }
                self.load()
            }
            .store(in: &cancellables)
    }
    
    func startLoadIfNeeded() {
        let authStatus = PhotoLibraryService.shared.authorizationStatus
        guard authStatus == .authorized || authStatus == .limited else { return }
        if !isLoading && !hasLoaded {
            load()
        }
    }
    
    func onAppear() {
        isActive = true
    }
    
    func onDisappear() {
        isActive = false
        // DO NOT cancel background loading
    }
    
    var totalCount: Int {
        if category == .largeVideos {
            return sortedLargeVideoAssets.count
        } else {
            return cursor?.count ?? 0
        }
    }
    
    func asset(at index: Int) -> PHAsset? {
        if category == .largeVideos {
            guard index >= 0 && index < sortedLargeVideoAssets.count else { return nil }
            return sortedLargeVideoAssets[index]
        } else {
            guard let cur = cursor, index >= 0 && index < cur.count else { return nil }
            return cur[index]
        }
    }
    
    /// Groups large videos into descending size tier sections (e.g. 10 GB & More, 1 GB – 10 GB, etc.).
    var videoSections: [VideoSizeSection] {
        var grouped: [VideoSizeTier: [PHAsset]] = [:]
        for asset in sortedLargeVideoAssets {
            let size = fileSizes[asset.localIdentifier] ?? 0
            let tier = VideoSizeTier.tier(for: size)
            grouped[tier, default: []].append(asset)
        }
        
        let sortedTiers = VideoSizeTier.allCases.sorted(by: >)
        return sortedTiers.compactMap { tier in
            guard let tierAssets = grouped[tier], !tierAssets.isEmpty else { return nil }
            let sortedInTier = tierAssets.sorted {
                (fileSizes[$0.localIdentifier] ?? 0) > (fileSizes[$1.localIdentifier] ?? 0)
            }
            let total = sortedInTier.reduce(0) { $0 + (fileSizes[$1.localIdentifier] ?? 0) }
            return VideoSizeSection(tier: tier, assets: sortedInTier, totalBytes: total)
        }
    }
    
    /// Incremental insertion for a newly discovered large video
    func appendLargeVideo(asset: PHAsset, size: Int64) {
        guard !fileSizes.keys.contains(asset.localIdentifier) else { return }
        fileSizes[asset.localIdentifier] = size
        sortedLargeVideoAssets.append(asset)
        sortedLargeVideoAssets.sort { (fileSizes[$0.localIdentifier] ?? 0) > (fileSizes[$1.localIdentifier] ?? 0) }
        hasLoaded = true
        onScanCompleted?()
    }
    
    // MARK: - Cold Launch Hydration
    
    func hydrateLargeVideos(sortedIds: [String], sizes: [String: Int64]) {
        guard sortedLargeVideoAssets.isEmpty && !hasLoaded else { return }
        guard !sortedIds.isEmpty else { return }
        
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: sortedIds, options: nil)
        var map = [String: PHAsset]()
        fetch.enumerateObjects { asset, _, _ in
            map[asset.localIdentifier] = asset
        }
        
        let hydrated = sortedIds.compactMap { map[$0] }
        guard !hydrated.isEmpty else { return }
        
        self.sortedLargeVideoAssets = hydrated
        self.fileSizes = sizes
        self.hasLoaded = true
        self.onScanCompleted?()
    }
    
    func load() {
        guard !isLoading else { return }
        loadTask?.cancel()
        loadTask = Task {
            await executeLoad()
        }
    }
    
    func executeLoad() async {
        let authStatus = PhotoLibraryService.shared.authorizationStatus
        guard authStatus == .authorized || authStatus == .limited else {
            self.isLoading = false
            self.progressMessage = nil
            return
        }
        
        guard !isLoading else {
            while isLoading {
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            return
        }
        
        isLoading = true
        hasLoaded = false
        progressMessage = "Loading assets…"
        progressFraction = 0.0
        
        switch category {
        case .screenshots:
            let result = PhotoLibraryService.shared.fetchScreenshotsCursor()
            self.cursor = FetchResultCollection(fetchResult: result)
            self.isLoading = false
            self.hasLoaded = true
            self.progressMessage = nil
            self.onScanCompleted?()
            
        case .videos:
            let result = PhotoLibraryService.shared.fetchVideosCursor()
            self.cursor = FetchResultCollection(fetchResult: result)
            self.isLoading = false
            self.hasLoaded = true
            self.progressMessage = nil
            self.onScanCompleted?()
            
        case .people:
            let result = PhotoLibraryService.shared.fetchPeopleAndPortraitsCursor()
            self.cursor = FetchResultCollection(fetchResult: result)
            self.isLoading = false
            self.hasLoaded = true
            self.progressMessage = nil
            self.onScanCompleted?()
            
        case .largeVideos:
            let stream = await MediaAnalyzerEngine.shared.streamLargeVideos(minThresholdBytes: 0)
            
            for await (sortedSnapshot, sizeMap, progress) in stream {
                if Task.isCancelled { break }
                // Atomic pointer swap: 0ms main thread cost, pre-sorted off MainActor
                self.sortedLargeVideoAssets = sortedSnapshot
                self.fileSizes = sizeMap
                self.progress = progress
                self.progressMessage = progress.stage
                self.progressFraction = progress.fractionCompleted
            }
            
            self.isLoading = false
            self.hasLoaded = !Task.isCancelled
            self.progressMessage = nil
            self.progress = nil
            self.onScanCompleted?()
            
            if !Task.isCancelled && !self.sortedLargeVideoAssets.isEmpty {
                let idsToSave = self.sortedLargeVideoAssets.map(\.localIdentifier)
                let sizesToSave = self.fileSizes
                Task.detached(priority: .utility) {
                    try? await PersistentClusterStore.shared.saveLargeVideoMetadata(
                        sortedAssetIds: idsToSave,
                        fileSizes: sizesToSave
                    )
                }
            }
            
        default:
            self.isLoading = false
            self.hasLoaded = true
            break
        }
    }
    
    /// Non-destructive in-place refresh for pull-to-refresh without wiping the view.
    func refresh() async {
        guard !isLoading && !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        
        switch category {
        case .screenshots:
            let result = PhotoLibraryService.shared.fetchScreenshotsCursor()
            withAnimation(.snappy) {
                self.cursor = FetchResultCollection(fetchResult: result)
                self.hasLoaded = true
            }
        case .videos:
            let result = PhotoLibraryService.shared.fetchVideosCursor()
            withAnimation(.snappy) {
                self.cursor = FetchResultCollection(fetchResult: result)
                self.hasLoaded = true
            }
        case .people:
            let result = PhotoLibraryService.shared.fetchPeopleAndPortraitsCursor()
            withAnimation(.snappy) {
                self.cursor = FetchResultCollection(fetchResult: result)
                self.hasLoaded = true
            }
        case .largeVideos:
            let stream = await MediaAnalyzerEngine.shared.streamLargeVideos(minThresholdBytes: 0)
            
            for await (sortedSnapshot, sizeMap, _) in stream {
                if Task.isCancelled { break }
                self.sortedLargeVideoAssets = sortedSnapshot
                self.fileSizes = sizeMap
            }
            self.hasLoaded = true
        default:
            break
        }
        self.onScanCompleted?()
    }
    
    func cancel() {
        loadTask?.cancel()
        loadTask = nil
        isLoading = false
        hasLoaded = false
        progressMessage = nil
        progress = nil
    }
    
    // MARK: - In-Memory Pruning
    
    func pruneDeletedAssets(_ deletedIds: Set<String>) {
        if category == .largeVideos {
            withAnimation(.snappy) {
                sortedLargeVideoAssets.removeAll { deletedIds.contains($0.localIdentifier) }
                for id in deletedIds {
                    fileSizes.removeValue(forKey: id)
                }
            }
        } else {
            // Re-fetch cursor instantly from SQLite
            if category == .screenshots {
                let result = PhotoLibraryService.shared.fetchScreenshotsCursor()
                self.cursor = FetchResultCollection(fetchResult: result)
            } else if category == .videos {
                let result = PhotoLibraryService.shared.fetchVideosCursor()
                self.cursor = FetchResultCollection(fetchResult: result)
            } else if category == .people {
                let result = PhotoLibraryService.shared.fetchPeopleAndPortraitsCursor()
                self.cursor = FetchResultCollection(fetchResult: result)
            }
        }
    }
    
    // MARK: - Smooth Prefetching
    func prefetch(around index: Int, window: Int = 30) {
        let total = totalCount
        guard total > 0 else { return }
        let startIndex = max(0, index - window)
        let endIndex = min(total, index + window)
        
        var slice: [PHAsset] = []
        for i in startIndex..<endIndex {
            if let a = asset(at: i) {
                slice.append(a)
            }
        }
        ThumbnailService.shared.startCaching(assets: slice)
    }
}
