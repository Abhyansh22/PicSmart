//
//  AppModel.swift
//  PicSmart
//

import Photos
import SwiftUI
import Observation

@Observable
@MainActor
final class AppModel {
    // Persistent session ViewModels
    let screenshotsViewModel = MediaCollectionViewModel(category: .screenshots)
    let videosViewModel = MediaCollectionViewModel(category: .videos)
    let largeVideosViewModel = MediaCollectionViewModel(category: .largeVideos)
    let favoritesViewModel = MediaCollectionViewModel(category: .favorites)
    let peopleViewModel = MediaCollectionViewModel(category: .people)
    
    let duplicatePhotosViewModel = GroupedScanViewModel(category: .duplicatePhotos)
    let duplicateVideosViewModel = GroupedScanViewModel(category: .duplicateVideos)
    let similarPhotosViewModel = GroupedScanViewModel(category: .similarPhotos)
    
    // Home badge counts
    var counts: [GalleryCategory: Int] = [:]
    var isLoadingCounts: Bool = false
    var lifetimeBytesSaved: Int64 = 0
    
    @ObservationIgnored
    private var countTask: Task<Void, Never>?
    
    init() {
        duplicatePhotosViewModel.onScanCompleted = { [weak self] in
            self?.refreshCounts()
        }
        duplicateVideosViewModel.onScanCompleted = { [weak self] in
            self?.refreshCounts()
        }
        similarPhotosViewModel.onScanCompleted = { [weak self] in
            self?.refreshCounts()
        }
        largeVideosViewModel.onScanCompleted = { [weak self] in
            self?.refreshCounts()
        }
        hydratePersistedClusters()
        refreshCounts()
        AnalysisPipelineCoordinator.shared.startProactiveBackgroundScan(appModel: self)
    }
    
    func hydratePersistedClusters() {
        Task {
            let dups = try? await PersistentClusterStore.shared.loadClusters(for: .duplicatePhotos)
            let sim = try? await PersistentClusterStore.shared.loadClusters(for: .similarPhotos)
            let dupVid = try? await PersistentClusterStore.shared.loadClusters(for: .duplicateVideos)
            let lifetime = (try? await PersistentClusterStore.shared.totalLifetimeBytesSaved()) ?? 0
            
            if let dups, !dups.isEmpty {
                self.duplicatePhotosViewModel.hydrate(from: dups)
            }
            if let sim, !sim.isEmpty {
                self.similarPhotosViewModel.hydrate(from: sim)
            }
            if let dupVid, !dupVid.isEmpty {
                self.duplicateVideosViewModel.hydrate(from: dupVid)
            }
            self.lifetimeBytesSaved = lifetime
            self.refreshCounts()
        }
    }
    
    func onPhotoAccessGranted() {
        if duplicatePhotosViewModel.groups.isEmpty {
            duplicatePhotosViewModel.hasCompletedScan = false
        }
        if similarPhotosViewModel.groups.isEmpty {
            similarPhotosViewModel.hasCompletedScan = false
        }
        if duplicateVideosViewModel.groups.isEmpty {
            duplicateVideosViewModel.hasCompletedScan = false
        }
        if largeVideosViewModel.sortedLargeVideoAssets.isEmpty {
            largeVideosViewModel.hasLoaded = false
        }
        
        hydratePersistedClusters()
        refreshCounts()
        AnalysisPipelineCoordinator.shared.startProactiveBackgroundScan(appModel: self, force: true)
    }
    
    // Direct reactive badge accessors so SwiftUI observes the child viewmodels directly
    func badgeCount(for category: GalleryCategory) -> Int? {
        switch category {
        case .screenshots:
            return counts[.screenshots]
        case .videos:
            return counts[.videos]
        case .favorites:
            return counts[.favorites]
        case .people:
            return counts[.people]
        case .largeVideos:
            return largeVideosViewModel.hasLoaded ? largeVideosViewModel.totalCount : counts[.largeVideos]
        case .duplicatePhotos:
            return duplicatePhotosViewModel.hasCompletedScan ? duplicatePhotosViewModel.totalRedundantCount : nil
        case .duplicateVideos:
            return duplicateVideosViewModel.hasCompletedScan ? duplicateVideosViewModel.totalRedundantCount : nil
        case .similarPhotos:
            return similarPhotosViewModel.hasCompletedScan ? similarPhotosViewModel.totalRedundantCount : nil
        }
    }
    
    func isScanning(for category: GalleryCategory) -> Bool {
        switch category {
        case .duplicatePhotos:
            return duplicatePhotosViewModel.isScanning || duplicatePhotosViewModel.isRefreshing
        case .duplicateVideos:
            return duplicateVideosViewModel.isScanning || duplicateVideosViewModel.isRefreshing
        case .similarPhotos:
            return similarPhotosViewModel.isScanning || similarPhotosViewModel.isRefreshing
        case .largeVideos:
            return largeVideosViewModel.isLoading || largeVideosViewModel.isRefreshing
        default:
            return false
        }
    }
    
    func refreshCounts() {
        countTask?.cancel()
        countTask = Task {
            isLoadingCounts = true
            
            // Tier 0 SQLite database queries: instant (< 1ms)
            async let scCount = PhotoLibraryService.shared.fetchScreenshotsCount()
            async let vCount = PhotoLibraryService.shared.fetchVideosCount()
            async let favCount = PhotoLibraryService.shared.fetchFavoritesCount()
            async let pplCount = PhotoLibraryService.shared.fetchPeopleAndPortraitsCount()
            
            let screenshots = await scCount
            let videos = await vCount
            let favorites = await favCount
            let people = await pplCount
            
            let threshold = AppSettings.shared.largeVideoThresholdBytes
            let cachedLv = await MediaAnalyzerEngine.shared.cachedLargeVideoCount(minThresholdBytes: threshold)
            
            if !Task.isCancelled {
                counts[.screenshots] = screenshots
                counts[.videos] = videos
                counts[.favorites] = favorites
                counts[.people] = people
                if let cachedLv {
                    counts[.largeVideos] = cachedLv
                } else if largeVideosViewModel.hasLoaded {
                    counts[.largeVideos] = largeVideosViewModel.totalCount
                }
                
                if duplicatePhotosViewModel.hasCompletedScan {
                    counts[.duplicatePhotos] = duplicatePhotosViewModel.totalRedundantCount
                }
                if duplicateVideosViewModel.hasCompletedScan {
                    counts[.duplicateVideos] = duplicateVideosViewModel.totalRedundantCount
                }
                if similarPhotosViewModel.hasCompletedScan {
                    counts[.similarPhotos] = similarPhotosViewModel.totalRedundantCount
                }
            }
            isLoadingCounts = false
        }
    }
    
    /// Centralized asset deletion coordinator.
    /// Deletes assets from PhotoKit, immediately prunes in-memory arrays and SwiftData clusters, and records cleanup history.
    @discardableResult
    func deleteAssets(localIdentifiers: [String], categoryTitle: String = "Media") async throws -> Set<String> {
        let deleted = try await PhotoLibraryService.shared.deleteAssets(localIdentifiers: localIdentifiers)
        guard !deleted.isEmpty else { return [] }
        
        // Calculate estimated size for the cleanup log
        var freedBytes: Int64 = 0
        for id in deleted {
            if let size = largeVideosViewModel.fileSizes[id] {
                freedBytes += size
            } else {
                freedBytes += 3_500_000 // Average photo size estimate ~3.5 MB
            }
        }
        
        // 1. Prune from grouped ViewModels
        duplicatePhotosViewModel.pruneDeletedAssets(deleted)
        duplicateVideosViewModel.pruneDeletedAssets(deleted)
        similarPhotosViewModel.pruneDeletedAssets(deleted)
        
        // 2. Prune from flat ViewModels
        largeVideosViewModel.pruneDeletedAssets(deleted)
        screenshotsViewModel.pruneDeletedAssets(deleted)
        videosViewModel.pruneDeletedAssets(deleted)
        favoritesViewModel.pruneDeletedAssets(deleted)
        peopleViewModel.pruneDeletedAssets(deleted)
        
        // 3. Prune SwiftData & record cleanup log
        let sampleIds = Array(deleted.prefix(4))
        let freed = freedBytes
        Task.detached(priority: .utility) {
            try? await PersistentClusterStore.shared.pruneDeletedAssets(deleted)
            try? await PersistentClusterStore.shared.recordCleanup(
                categoryTitle: categoryTitle,
                itemCount: deleted.count,
                bytesSaved: freed,
                sampleIdentifiers: sampleIds
            )
        }
        
        lifetimeBytesSaved += freedBytes
        
        // 4. Immediately update counts
        refreshCounts()
        
        return deleted
    }
    
    func groupedViewModel(for category: GalleryCategory) -> GroupedScanViewModel {
        switch category {
        case .duplicatePhotos: return duplicatePhotosViewModel
        case .duplicateVideos: return duplicateVideosViewModel
        case .similarPhotos: return similarPhotosViewModel
        default: return duplicatePhotosViewModel
        }
    }
    
    func mediaViewModel(for category: GalleryCategory) -> MediaCollectionViewModel {
        switch category {
        case .screenshots: return screenshotsViewModel
        case .videos: return videosViewModel
        case .largeVideos: return largeVideosViewModel
        case .favorites: return favoritesViewModel
        case .people: return peopleViewModel
        default: return screenshotsViewModel
        }
    }
}
