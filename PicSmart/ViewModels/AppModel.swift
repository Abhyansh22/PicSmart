//
//  AppModel.swift
//  PicSmart
//

import Photos
import SwiftUI
import Observation
import Combine

@Observable
@MainActor
final class AppModel {
    // Persistent session ViewModels
    let screenshotsViewModel = MediaCollectionViewModel(category: .screenshots)
    let videosViewModel = MediaCollectionViewModel(category: .videos)
    let largeVideosViewModel = MediaCollectionViewModel(category: .largeVideos)
    let blurredPhotosViewModel = BlurredPhotosViewModel()
    let peopleAndFacesViewModel = PeopleAndFacesViewModel()
    
    let duplicatePhotosViewModel = GroupedScanViewModel(category: .duplicatePhotos)
    let duplicateVideosViewModel = GroupedScanViewModel(category: .duplicateVideos)
    let similarPhotosViewModel = GroupedScanViewModel(category: .similarPhotos)
    
    // Home badge counts
    var counts: [GalleryCategory: Int] = [:]
    var isLoadingCounts: Bool = false
    var lifetimeBytesSaved: Int64 = 0
    
    @ObservationIgnored
    private var countTask: Task<Void, Never>?
    @ObservationIgnored
    private var deltaSyncTask: Task<Void, Never>?
    @ObservationIgnored
    private var cancellables = Set<AnyCancellable>()
    
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
        blurredPhotosViewModel.onScanCompleted = { [weak self] in
            self?.refreshCounts()
        }
        peopleAndFacesViewModel.onScanCompleted = { [weak self] in
            self?.refreshCounts()
        }
        
        // Listen to system PhotoKit changes across the entire app
        PhotoLibraryService.shared.libraryChangePublisher
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.runDeltaSync()
            }
            .store(in: &cancellables)
            
        hydratePersistedClusters()
        refreshCounts()
        AnalysisPipelineCoordinator.shared.startProactiveBackgroundScan(appModel: self)
    }
    
    func hydratePersistedClusters() {
        Task {
            let dups = try? await PersistentClusterStore.shared.loadClusters(for: .duplicatePhotos)
            let sim = try? await PersistentClusterStore.shared.loadClusters(for: .similarPhotos)
            let dupVid = try? await PersistentClusterStore.shared.loadClusters(for: .duplicateVideos)
            let persons = try? await PersistentClusterStore.shared.loadPersonDTOs()
            let blurred = await BlurredPhotosFunnel.shared.loadCachedBlurredItems()
            let largeVideoMeta = try? await PersistentClusterStore.shared.loadLargeVideoMetadata()
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
            if let persons, !persons.isEmpty {
                self.peopleAndFacesViewModel.hydrate(from: persons)
                self.counts[.people] = self.peopleAndFacesViewModel.totalCount
            }
            if !blurred.isEmpty {
                self.blurredPhotosViewModel.hydrate(from: blurred)
                self.counts[.blurredPhotos] = self.blurredPhotosViewModel.totalCount
            }
            if let largeVideoMeta {
                self.largeVideosViewModel.hydrateLargeVideos(
                    sortedIds: largeVideoMeta.sortedAssetIds,
                    sizes: largeVideoMeta.fileSizes
                )
                await MediaAnalyzerEngine.shared.setCachedVideoSizes(largeVideoMeta.fileSizes)
            }
            self.lifetimeBytesSaved = lifetime
            self.refreshCounts()
            self.runDeltaSync()
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
        if blurredPhotosViewModel.items.isEmpty {
            blurredPhotosViewModel.hasCompletedScan = false
        }
        if peopleAndFacesViewModel.personClusters.isEmpty {
            peopleAndFacesViewModel.hasCompletedScan = false
        }
        
        hydratePersistedClusters()
        refreshCounts()
        runDeltaSync()
        AnalysisPipelineCoordinator.shared.startProactiveBackgroundScan(appModel: self, force: false)
    }
    
    // MARK: - Incremental Delta Synchronization
    
    func runDeltaSync() {
        deltaSyncTask?.cancel()
        deltaSyncTask = Task {
            let delta = await LibraryDeltaTracker.shared.checkForDeltas()
            guard !Task.isCancelled else { return }
            
            // 1. Prune externally deleted assets
            if !delta.deletedAssetIds.isEmpty {
                self.pruneDeletedAssetsAcrossModels(delta.deletedAssetIds)
            }
            
            // 2. Process newly added assets incrementally
            if !delta.addedAssets.isEmpty {
                await self.processAddedAssets(delta.addedAssets)
            }
            
            self.refreshCounts()
        }
    }
    
    /// Prunes deleted assets across all view models and SwiftData clusters without re-scanning
    func pruneDeletedAssetsAcrossModels(_ deleted: Set<String>) {
        duplicatePhotosViewModel.pruneDeletedAssets(deleted)
        duplicateVideosViewModel.pruneDeletedAssets(deleted)
        similarPhotosViewModel.pruneDeletedAssets(deleted)
        blurredPhotosViewModel.pruneDeletedAssets(deleted)
        peopleAndFacesViewModel.pruneDeletedAssets(deleted)
        largeVideosViewModel.pruneDeletedAssets(deleted)
        screenshotsViewModel.pruneDeletedAssets(deleted)
        videosViewModel.pruneDeletedAssets(deleted)
        
        Task.detached(priority: .utility) {
            try? await PersistentClusterStore.shared.pruneDeletedAssets(deleted)
        }
        refreshCounts()
    }
    
    /// Incremental analysis of newly added media items
    private func processAddedAssets(_ assets: [PHAsset]) async {
        guard !assets.isEmpty else { return }
        
        for asset in assets {
            if Task.isCancelled { break }
            
            if asset.mediaType == .video {
                // Record video into large videos repository
                let size = asset.primaryResourceFileSize ?? 0
                self.largeVideosViewModel.appendLargeVideo(asset: asset, size: size)
            } else if asset.mediaType == .image {
                // 1. Evaluate Blur immediately
                if let blurred = await BlurredPhotosFunnel.shared.evaluateSingleAsset(asset) {
                    self.blurredPhotosViewModel.appendItem(blurred)
                }
                
                // 2. Evaluate Exact Duplicate against existing duplicate groups
                let size = asset.primaryResourceFileSize ?? 0
                if size > 0 {
                    var matchedGroupIndex: Int? = nil
                    for (idx, group) in duplicatePhotosViewModel.groups.enumerated() {
                        if let first = group.assets.first,
                           first.pixelWidth == asset.pixelWidth,
                           first.pixelHeight == asset.pixelHeight,
                           group.fileSizes[first.localIdentifier] == size {
                            matchedGroupIndex = idx
                            break
                        }
                    }
                    if let idx = matchedGroupIndex {
                        duplicatePhotosViewModel.groups[idx].assets.append(asset)
                        duplicatePhotosViewModel.groups[idx].fileSizes[asset.localIdentifier] = size
                        duplicatePhotosViewModel.groups[idx].markedForDeletionIds.insert(asset.localIdentifier)
                        let updated = duplicatePhotosViewModel.groups
                        Task.detached(priority: .utility) {
                            try? await PersistentClusterStore.shared.saveClusters(updated, for: .duplicatePhotos)
                        }
                    }
                }
                
                // 3. Incremental People & Faces Clustering
                let existingDTOs = (try? await PersistentClusterStore.shared.loadPersonDTOs()) ?? []
                if let faceResult = await PeopleAnalysisEngine.shared.processNewAssetIncrementally(asset, existingClusters: existingDTOs) {
                    self.peopleAndFacesViewModel.applyIncrementalFaceResult(faceResult)
                }
            }
        }
    }
    
    // Direct reactive badge accessors so SwiftUI observes the child viewmodels directly
    func badgeCount(for category: GalleryCategory) -> Int? {
        switch category {
        case .screenshots:
            return counts[.screenshots]
        case .videos:
            return counts[.videos]
        case .blurredPhotos:
            return blurredPhotosViewModel.hasCompletedScan ? blurredPhotosViewModel.totalCount : counts[.blurredPhotos]
        case .people:
            return (peopleAndFacesViewModel.hasCompletedScan || !peopleAndFacesViewModel.personClusters.isEmpty)
                ? peopleAndFacesViewModel.totalCount
                : counts[.people]
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
        case .blurredPhotos:
            return blurredPhotosViewModel.isScanning || blurredPhotosViewModel.isRefreshing
        case .people:
            return peopleAndFacesViewModel.isScanning || peopleAndFacesViewModel.isRefreshing
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
            
            let screenshots = await scCount
            let videos = await vCount
            
            let cachedLv = await MediaAnalyzerEngine.shared.cachedLargeVideoCount(minThresholdBytes: 0)
            
            if !Task.isCancelled {
                counts[.screenshots] = screenshots
                counts[.videos] = videos
                if let cachedLv {
                    counts[.largeVideos] = cachedLv
                } else if largeVideosViewModel.hasLoaded {
                    counts[.largeVideos] = largeVideosViewModel.totalCount
                }
                
                if blurredPhotosViewModel.hasCompletedScan {
                    counts[.blurredPhotos] = blurredPhotosViewModel.totalCount
                }
                if peopleAndFacesViewModel.hasCompletedScan {
                    counts[.people] = peopleAndFacesViewModel.totalCount
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
        
        // 2. Prune from specialized & flat ViewModels
        blurredPhotosViewModel.pruneDeletedAssets(deleted)
        peopleAndFacesViewModel.pruneDeletedAssets(deleted)
        largeVideosViewModel.pruneDeletedAssets(deleted)
        screenshotsViewModel.pruneDeletedAssets(deleted)
        videosViewModel.pruneDeletedAssets(deleted)
        
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
        default: return screenshotsViewModel
        }
    }
}
