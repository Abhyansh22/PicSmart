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
    
    // For Large Videos: sorted array streaming from engine
    var largeVideoAssets: [PHAsset] = []
    var fileSizes: [String: Int64] = [:]
    
    var isLoading: Bool = false
    var progressMessage: String?
    var progressFraction: Double = 0.0
    
    @ObservationIgnored
    private var loadTask: Task<Void, Never>?
    @ObservationIgnored
    private var cancellables = Set<AnyCancellable>()
    
    init(category: GalleryCategory) {
        self.category = category
        
        PhotoLibraryService.shared.libraryChangePublisher
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.load()
            }
            .store(in: &cancellables)
    }
    
    var totalCount: Int {
        if category == .largeVideos {
            return largeVideoAssets.count
        } else {
            return cursor?.count ?? 0
        }
    }
    
    func asset(at index: Int) -> PHAsset? {
        if category == .largeVideos {
            guard index >= 0 && index < largeVideoAssets.count else { return nil }
            return largeVideoAssets[index]
        } else {
            guard let cur = cursor, index >= 0 && index < cur.count else { return nil }
            return cur[index]
        }
    }
    
    func load() {
        loadTask?.cancel()
        loadTask = Task {
            isLoading = true
            progressMessage = "Loading assets…"
            progressFraction = 0.0
            
            switch category {
            case .screenshots:
                let result = PhotoLibraryService.shared.fetchScreenshotsCursor()
                self.cursor = FetchResultCollection(fetchResult: result)
                self.isLoading = false
                self.progressMessage = nil
                
            case .videos:
                let result = PhotoLibraryService.shared.fetchVideosCursor()
                self.cursor = FetchResultCollection(fetchResult: result)
                self.isLoading = false
                self.progressMessage = nil
                
            case .largeVideos:
                let threshold = AppSettings.shared.largeVideoThresholdBytes
                let stream = await MediaAnalyzerEngine.shared.streamLargeVideos(minThresholdBytes: threshold)
                
                for await (sortedSnapshot, sizeMap, progress) in stream {
                    if Task.isCancelled { break }
                    self.largeVideoAssets = sortedSnapshot
                    self.fileSizes = sizeMap
                    self.progressMessage = progress.stage
                    self.progressFraction = progress.fractionCompleted
                }
                
                self.isLoading = false
                self.progressMessage = nil
                
            default:
                self.isLoading = false
                break
            }
        }
    }
    
    func cancel() {
        loadTask?.cancel()
        loadTask = nil
        isLoading = false
        progressMessage = nil
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
