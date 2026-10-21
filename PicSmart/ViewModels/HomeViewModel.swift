//
//  HomeViewModel.swift
//  PicSmart
//

import Photos
import SwiftUI
import Combine
import Observation

@Observable
@MainActor
final class HomeViewModel {
    var counts: [GalleryCategory: Int] = [:]
    var isLoadingCounts: Bool = false
    var isViewActive: Bool = false
    
    @ObservationIgnored
    private var cancellables = Set<AnyCancellable>()
    @ObservationIgnored
    private var countTask: Task<Void, Never>?
    
    init() {
        PhotoLibraryService.shared.libraryChangePublisher
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.isViewActive else { return }
                self.refreshCounts()
            }
            .store(in: &cancellables)
    }
    
    func onAppear() {
        isViewActive = true
        refreshCounts()
    }
    
    func onDisappear() {
        isViewActive = false
        countTask?.cancel()
    }
    
    func refreshCounts() {
        countTask?.cancel()
        countTask = Task {
            isLoadingCounts = true
            
            // Tier 0 SQLite database queries: instant (< 1ms)
            async let scCount = PhotoLibraryService.shared.fetchScreenshotsCount()
            async let vCount = PhotoLibraryService.shared.fetchVideosCount()
            
            let screenshots = await scCount
            let videos = await vCount
            
            // Fast in-memory check for large video count without blocking IPC
            let threshold = AppSettings.shared.largeVideoThresholdBytes
            let cachedLv = await MediaAnalyzerEngine.shared.cachedLargeVideoCount(minThresholdBytes: threshold)
            
            if !Task.isCancelled {
                counts[.screenshots] = screenshots
                counts[.videos] = videos
                if let cachedLv {
                    counts[.largeVideos] = cachedLv
                } else {
                    counts.removeValue(forKey: .largeVideos)
                }
            }
            isLoadingCounts = false
        }
    }
}
