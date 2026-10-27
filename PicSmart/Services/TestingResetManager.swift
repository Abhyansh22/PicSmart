//
//  TestingResetManager.swift
//  PicSmart
//

#if DEBUG
import Foundation
import SwiftData
import SwiftUI

@MainActor
final class TestingResetManager {
    static func resetAll(appModel: AppModel) async {
        // 1. Cancel in-flight coordinator and view model scanning tasks
        AnalysisPipelineCoordinator.shared.cancel()
        appModel.duplicatePhotosViewModel.cancel()
        appModel.similarPhotosViewModel.cancel()
        appModel.duplicateVideosViewModel.cancel()
        appModel.blurredPhotosViewModel.cancel()
        appModel.peopleAndFacesViewModel.cancel()
        appModel.largeVideosViewModel.cancel()
        
        // 2. Wipe SwiftData persistent store tables
        await PersistentClusterStore.shared.resetAllData()
        
        // 3. Reset UserDefaults & Delta Sync checkpoints
        UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
        await LibraryDeltaTracker.shared.resetCheckpoints()
        
        // 4. Reset in-memory ViewModels to zero state
        appModel.duplicatePhotosViewModel.groups = []
        appModel.duplicatePhotosViewModel.hasCompletedScan = false
        
        appModel.similarPhotosViewModel.groups = []
        appModel.similarPhotosViewModel.hasCompletedScan = false
        
        appModel.duplicateVideosViewModel.groups = []
        appModel.duplicateVideosViewModel.hasCompletedScan = false
        
        appModel.blurredPhotosViewModel.items = []
        appModel.blurredPhotosViewModel.hasCompletedScan = false
        
        appModel.peopleAndFacesViewModel.personClusters = []
        appModel.peopleAndFacesViewModel.items = []
        appModel.peopleAndFacesViewModel.hasCompletedScan = false
        
        appModel.largeVideosViewModel.sortedLargeVideoAssets = []
        appModel.largeVideosViewModel.fileSizes = [:]
        appModel.largeVideosViewModel.hasLoaded = false
        
        appModel.screenshotsViewModel.cursor = nil
        appModel.screenshotsViewModel.hasLoaded = false
        
        appModel.videosViewModel.cursor = nil
        appModel.videosViewModel.hasLoaded = false
        
        appModel.lifetimeBytesSaved = 0
        appModel.counts.removeAll()
        
        // 5. Re-run initial discovery as fresh install
        appModel.refreshCounts()
        AnalysisPipelineCoordinator.shared.startProactiveBackgroundScan(appModel: appModel, force: true)
    }
}

extension PersistentClusterStore {
    func resetAllData() {
        try? modelContext.delete(model: CachedVisualSignature.self)
        try? modelContext.delete(model: PersistentAssetCluster.self)
        try? modelContext.delete(model: CleanupSessionRecord.self)
        try? modelContext.delete(model: PersistentPersonCluster.self)
        try? modelContext.delete(model: CachedFaceEmbedding.self)
        try? modelContext.save()
    }
}
#endif
