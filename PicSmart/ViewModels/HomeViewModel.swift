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
    
    @ObservationIgnored
    private var cancellables = Set<AnyCancellable>()
    @ObservationIgnored
    private var countTask: Task<Void, Never>?
    
    init() {
        PhotoLibraryService.shared.libraryChangePublisher
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshCounts()
            }
            .store(in: &cancellables)
    }
    
    func refreshCounts() {
        countTask?.cancel()
        countTask = Task {
            isLoadingCounts = true
            
            async let scCount = PhotoLibraryService.shared.fetchScreenshotsCount()
            async let vCount = PhotoLibraryService.shared.fetchVideosCount()
            let threshold = AppSettings.shared.largeVideoThresholdBytes
            async let lvCount = MediaAnalyzerEngine.shared.countLargeVideos(minThresholdBytes: threshold)
            
            let screenshots = await scCount
            let videos = await vCount
            let largeVideos = await lvCount
            
            if !Task.isCancelled {
                counts[.screenshots] = screenshots
                counts[.videos] = videos
                counts[.largeVideos] = largeVideos
            }
            isLoadingCounts = false
        }
    }
}
