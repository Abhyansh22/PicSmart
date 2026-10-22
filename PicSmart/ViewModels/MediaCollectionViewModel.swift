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
        if !isLoading && (!hasLoaded || totalCount == 0) {
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
            
        case .favorites:
            let result = PhotoLibraryService.shared.fetchFavoritesCursor()
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
            let threshold = AppSettings.shared.largeVideoThresholdBytes
            let stream = await MediaAnalyzerEngine.shared.streamLargeVideos(minThresholdBytes: threshold)
            
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
            self.hasLoaded = true
            self.progressMessage = nil
            self.progress = nil
            self.onScanCompleted?()
            
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
        case .favorites:
            let result = PhotoLibraryService.shared.fetchFavoritesCursor()
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
            let threshold = AppSettings.shared.largeVideoThresholdBytes
            let stream = await MediaAnalyzerEngine.shared.streamLargeVideos(minThresholdBytes: threshold)
            
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
        hasLoaded = true
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
            } else if category == .favorites {
                let result = PhotoLibraryService.shared.fetchFavoritesCursor()
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
