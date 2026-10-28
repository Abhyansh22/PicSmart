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
        screenshotsViewModel.onScanCompleted = { [weak self] in
            self?.refreshCounts()
        }
        videosViewModel.onScanCompleted = { [weak self] in
            self?.refreshCounts()
        }
        
        // Listen to system PhotoKit changes across the entire app
        PhotoLibraryService.shared.libraryChangePublisher
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.runDeltaSync()
            }
            .store(in: &cancellables)
            
        let auth = PhotoLibraryService.shared.authorizationStatus
        if auth == .authorized || auth == .limited {
            hydratePersistedClusters()
            refreshCounts()
            AnalysisPipelineCoordinator.shared.startProactiveBackgroundScan(appModel: self)
        }
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
            let totalImages = PhotoLibraryService.shared.fetchTotalImageCount()
            let allBlurRecords = (try? await PersistentClusterStore.shared.loadAllBlurRecords()) ?? [:]
            let isBlurComplete = totalImages > 0 && allBlurRecords.count >= totalImages
            
            let allFaceRecords = (try? await PersistentClusterStore.shared.loadAllFaceEmbeddings()) ?? []
            let evaluatedFaceAssetCount = Set(allFaceRecords.map(\.assetIdentifier)).count
            let isPeopleComplete = (totalImages > 0 && evaluatedFaceAssetCount >= totalImages)
                || UserDefaults.standard.bool(forKey: "isPeopleScanComplete")
            
            if let persons, !persons.isEmpty {
                self.peopleAndFacesViewModel.hydrate(from: persons, isFullyEvaluated: isPeopleComplete)
                self.counts[.people] = self.peopleAndFacesViewModel.totalCount
            } else if isPeopleComplete {
                self.peopleAndFacesViewModel.hasCompletedScan = true
                self.counts[.people] = 0
            }
            if !blurred.isEmpty {
                self.blurredPhotosViewModel.hydrate(from: blurred, isFullyEvaluated: isBlurComplete)
                self.counts[.blurredPhotos] = self.blurredPhotosViewModel.totalCount
            } else if isBlurComplete {
                self.blurredPhotosViewModel.hasCompletedScan = true
                self.counts[.blurredPhotos] = 0
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
    
    // MARK: - Background Lifecycle Management
    
    func handleDidEnterBackground() {
        var bgTaskId = UIBackgroundTaskIdentifier.invalid
        bgTaskId = UIApplication.shared.beginBackgroundTask(withName: "PicSmart.LifecycleFlush") {
            // Watchdog deadline reached: force suspend and end background task immediately
            AnalysisPipelineCoordinator.shared.suspendForBackground()
            if bgTaskId != .invalid {
                UIApplication.shared.endBackgroundTask(bgTaskId)
                bgTaskId = .invalid
            }
        }
        
        Task {
            // Suspend background pipeline to pause thread/ANE consumption
            AnalysisPipelineCoordinator.shared.suspendForBackground()
            
            // Allow a short 500ms window for any pending batch to complete disk flush
            try? await Task.sleep(nanoseconds: 500_000_000)
            
            if bgTaskId != .invalid {
                UIApplication.shared.endBackgroundTask(bgTaskId)
                bgTaskId = .invalid
            }
        }
    }
    
    func handleDidBecomeActive() {
        AnalysisPipelineCoordinator.shared.resumeFromBackground()
        runDeltaSync()
    }
    
    func onPhotoAccessGranted() {
        AnalysisPipelineCoordinator.shared.resumeFromBackground()
        
        // Immediately populate instantaneous Tier 0 counts synchronously
        counts[.screenshots] = PhotoLibraryService.shared.fetchScreenshotsCount()
        counts[.videos] = PhotoLibraryService.shared.fetchVideosCount()
        
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
        if peopleAndFacesViewModel.items.isEmpty {
            peopleAndFacesViewModel.hasCompletedScan = false
        }
        
        hydratePersistedClusters()
        refreshCounts()
        runDeltaSync()
        AnalysisPipelineCoordinator.shared.startProactiveBackgroundScan(appModel: self, force: true)
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
    
    // MARK: - Category Lifecycle Status
    
    func status(for category: GalleryCategory) -> CategoryStatus {
        switch category {
        case .screenshots:
            if screenshotsViewModel.hasLoaded {
                return .completed(count: screenshotsViewModel.totalCount)
            }
            if let count = counts[.screenshots] {
                return .completed(count: count)
            }
            return .notStarted
            
        case .videos:
            if videosViewModel.hasLoaded {
                return .completed(count: videosViewModel.totalCount)
            }
            if let count = counts[.videos] {
                return .completed(count: count)
            }
            return .notStarted
            
        case .largeVideos:
            if (largeVideosViewModel.isLoading || largeVideosViewModel.isRefreshing || AnalysisPipelineCoordinator.shared.slot1ActiveCategory == .largeVideos) && !largeVideosViewModel.hasLoaded {
                let prog = largeVideosViewModel.progress
                return .analyzing(
                    progress: prog?.fractionCompleted ?? 0,
                    stage: prog?.stage ?? "Analyzing…",
                    completed: prog?.completed ?? largeVideosViewModel.totalCount,
                    total: prog?.total ?? 0
                )
            }
            if largeVideosViewModel.hasLoaded {
                return .completed(count: largeVideosViewModel.totalCount)
            }
            if let count = counts[.largeVideos], count > 0 {
                return .paused(completed: count, total: 0)
            }
            return .notStarted
            
        case .duplicatePhotos:
            if (duplicatePhotosViewModel.isScanning || duplicatePhotosViewModel.isRefreshing || AnalysisPipelineCoordinator.shared.slot1ActiveCategory == .duplicatePhotos) && !duplicatePhotosViewModel.hasCompletedScan {
                let prog = duplicatePhotosViewModel.progress
                return .analyzing(
                    progress: prog?.fractionCompleted ?? 0,
                    stage: prog?.stage ?? "Scanning…",
                    completed: prog?.completed ?? duplicatePhotosViewModel.totalRedundantCount,
                    total: prog?.total ?? 0
                )
            }
            if duplicatePhotosViewModel.hasCompletedScan {
                return .completed(count: duplicatePhotosViewModel.totalRedundantCount)
            }
            if duplicatePhotosViewModel.totalRedundantCount > 0 {
                return .paused(completed: duplicatePhotosViewModel.totalRedundantCount, total: 0)
            }
            if let count = counts[.duplicatePhotos], count > 0 {
                return .paused(completed: count, total: 0)
            }
            return .notStarted
            
        case .duplicateVideos:
            if (duplicateVideosViewModel.isScanning || duplicateVideosViewModel.isRefreshing || AnalysisPipelineCoordinator.shared.slot1ActiveCategory == .duplicateVideos) && !duplicateVideosViewModel.hasCompletedScan {
                let prog = duplicateVideosViewModel.progress
                return .analyzing(
                    progress: prog?.fractionCompleted ?? 0,
                    stage: prog?.stage ?? "Scanning…",
                    completed: prog?.completed ?? duplicateVideosViewModel.totalRedundantCount,
                    total: prog?.total ?? 0
                )
            }
            if duplicateVideosViewModel.hasCompletedScan {
                return .completed(count: duplicateVideosViewModel.totalRedundantCount)
            }
            if duplicateVideosViewModel.totalRedundantCount > 0 {
                return .paused(completed: duplicateVideosViewModel.totalRedundantCount, total: 0)
            }
            if let count = counts[.duplicateVideos], count > 0 {
                return .paused(completed: count, total: 0)
            }
            return .notStarted
            
        case .similarPhotos:
            if (similarPhotosViewModel.isScanning || similarPhotosViewModel.isRefreshing || AnalysisPipelineCoordinator.shared.slot1ActiveCategory == .similarPhotos) && !similarPhotosViewModel.hasCompletedScan {
                let prog = similarPhotosViewModel.progress
                return .analyzing(
                    progress: prog?.fractionCompleted ?? 0,
                    stage: prog?.stage ?? "Scanning…",
                    completed: prog?.completed ?? similarPhotosViewModel.totalRedundantCount,
                    total: prog?.total ?? 0
                )
            }
            if similarPhotosViewModel.hasCompletedScan {
                return .completed(count: similarPhotosViewModel.totalRedundantCount)
            }
            if similarPhotosViewModel.totalRedundantCount > 0 {
                return .paused(completed: similarPhotosViewModel.totalRedundantCount, total: 0)
            }
            if let count = counts[.similarPhotos], count > 0 {
                return .paused(completed: count, total: 0)
            }
            return .notStarted
            
        case .blurredPhotos:
            if (blurredPhotosViewModel.isScanning || blurredPhotosViewModel.isRefreshing || AnalysisPipelineCoordinator.shared.slot1ActiveCategory == .blurredPhotos) && !blurredPhotosViewModel.hasCompletedScan {
                let prog = blurredPhotosViewModel.progress
                return .analyzing(
                    progress: prog?.fractionCompleted ?? 0,
                    stage: prog?.stage ?? "Scanning…",
                    completed: prog?.completed ?? blurredPhotosViewModel.totalCount,
                    total: prog?.total ?? 0
                )
            }
            if blurredPhotosViewModel.hasCompletedScan {
                return .completed(count: blurredPhotosViewModel.totalCount)
            }
            if !blurredPhotosViewModel.items.isEmpty {
                return .paused(completed: blurredPhotosViewModel.totalCount, total: 0)
            }
            if let count = counts[.blurredPhotos], count > 0 {
                return .paused(completed: count, total: 0)
            }
            return .notStarted
            
        case .people:
            if (peopleAndFacesViewModel.isScanning || peopleAndFacesViewModel.isRefreshing || AnalysisPipelineCoordinator.shared.slot1ActiveCategory == .people) && !peopleAndFacesViewModel.hasCompletedScan {
                let prog = peopleAndFacesViewModel.progress
                return .analyzing(
                    progress: prog?.fractionCompleted ?? 0,
                    stage: prog?.stage ?? "Scanning…",
                    completed: prog?.completed ?? peopleAndFacesViewModel.totalCount,
                    total: prog?.total ?? 0
                )
            }
            if peopleAndFacesViewModel.hasCompletedScan {
                return .completed(count: peopleAndFacesViewModel.totalCount)
            }
            if peopleAndFacesViewModel.totalCount > 0 {
                return .paused(completed: peopleAndFacesViewModel.totalCount, total: 0)
            }
            if let count = counts[.people], count > 0 {
                return .paused(completed: count, total: 0)
            }
            return .notStarted
        }
    }
    
    // Direct reactive badge accessors so SwiftUI observes the child viewmodels directly
    func badgeCount(for category: GalleryCategory) -> Int? {
        status(for: category).count
    }
    
    func isScanning(for category: GalleryCategory) -> Bool {
        status(for: category).isAnalyzing
    }
    
    func refreshCounts() {
        // Fast Tier 0 counts fetched synchronously on MainActor (< 1ms)
        let screenshots = PhotoLibraryService.shared.fetchScreenshotsCount()
        let videos = PhotoLibraryService.shared.fetchVideosCount()
        counts[.screenshots] = screenshots
        counts[.videos] = videos
        
        countTask?.cancel()
        countTask = Task {
            isLoadingCounts = true
            
            let cachedLv = await MediaAnalyzerEngine.shared.cachedLargeVideoCount(minThresholdBytes: 0)
            
            if !Task.isCancelled {
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
