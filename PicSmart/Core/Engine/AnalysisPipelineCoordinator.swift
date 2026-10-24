//
//  AnalysisPipelineCoordinator.swift
//  PicSmart
//

import Photos
import SwiftUI
import Observation

/// Priority level for media analysis tasks.
public enum AnalysisPriority: Int, Comparable, Sendable {
    case background = 0
    case userActive = 1
    
    public static func < (lhs: AnalysisPriority, rhs: AnalysisPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Central coordinator managing sequential background analysis on launch,
/// dynamic priority elevation when a user opens a screen, and cooperative preemption.
@Observable
@MainActor
final class AnalysisPipelineCoordinator {
    static let shared = AnalysisPipelineCoordinator()
    
    /// The category currently open on screen by the user.
    /// When set, this category gets top priority (.userActive).
    var activeCategory: GalleryCategory? = nil
    
    @ObservationIgnored
    private var backgroundPipelineTask: Task<Void, Never>?
    
    /// Sequential order of background analysis based on computational complexity:
    /// Tier 1: Large Videos (~100ms) -> Exact Duplicate Photos (~250ms)
    /// Tier 2: Duplicate Videos (~200ms) -> Blurred Photos (~500ms)
    /// Tier 3: Similar Photos (~2-5s, heaviest)
    /// (Note: People & Faces is decoupled and scheduled ONLY during idle phase due to 1024px Vision load)
    @ObservationIgnored
    private let backgroundSequence: [GalleryCategory] = [
        .largeVideos,
        .duplicatePhotos,
        .duplicateVideos,
        .blurredPhotos,
        .similarPhotos
    ]
    
    private init() {}
    
    // MARK: - Priority Management
    
    /// Called when the user navigates into a category screen.
    func elevatePriority(for category: GalleryCategory, in appModel: AppModel? = nil) {
        activeCategory = category
        if let appModel {
            switch category {
            case .duplicatePhotos:
                appModel.duplicatePhotosViewModel.startScanIfNeeded()
            case .duplicateVideos:
                appModel.duplicateVideosViewModel.startScanIfNeeded()
            case .similarPhotos:
                appModel.similarPhotosViewModel.startScanIfNeeded()
            case .largeVideos:
                appModel.largeVideosViewModel.startLoadIfNeeded()
            case .blurredPhotos:
                appModel.blurredPhotosViewModel.startScanIfNeeded()
            case .people:
                appModel.peopleAndFacesViewModel.startScanIfNeeded()
            default:
                break
            }
        }
    }
    
    /// Called when the user leaves the category screen.
    func releasePriority(for category: GalleryCategory) {
        if activeCategory == category {
            activeCategory = nil
        }
    }
    
    /// Checks if a category should cooperatively yield its CPU/worker slots
    /// because the user has navigated into a different category screen.
    nonisolated func shouldYield(for category: GalleryCategory) async -> Bool {
        let active = await MainActor.run { self.activeCategory }
        guard let active else { return false }
        return active != category
    }
    
    /// Cooperatively suspends background execution if the user is currently viewing
    /// a different category screen, resuming automatically when the user returns.
    /// Preserves all in-flight state and cached signatures without discarding progress.
    nonisolated func yieldIfPreempted(for category: GalleryCategory) async {
        while await shouldYield(for: category) {
            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms cooperative wait
        }
    }
    
    // MARK: - Proactive Background Pipeline
    
    /// Starts sequential background analysis across all heavy categories.
    /// Initiated on app launch after Tier 0 instant counts are resolved.
    func startProactiveBackgroundScan(appModel: AppModel, force: Bool = false) {
        if force {
            backgroundPipelineTask?.cancel()
            backgroundPipelineTask = nil
        }
        guard backgroundPipelineTask == nil else { return }
        
        let status = PhotoLibraryService.shared.authorizationStatus
        guard status == .authorized || status == .limited else {
            return
        }
        
        backgroundPipelineTask = Task.detached(priority: .utility) { [weak self, weak appModel] in
            guard let self, let appModel else { return }
            
            // Allow home screen push/transition to settle cleanly
            try? await Task.sleep(nanoseconds: 500_000_000)
            
            for category in self.backgroundSequence {
                if Task.isCancelled { break }
                
                // 1. Cooperative yield if user is actively viewing a different category
                while await self.shouldYield(for: category) {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                }
                
                // 2. Check if category is already completed
                let isDone = await MainActor.run {
                    self.isCategoryCompleted(category, in: appModel)
                }
                if isDone { continue }
                
                // 3. Execute category scan sequentially
                await self.runCategoryScan(category, in: appModel)
            }
            
            // 4. Idle Phase: Heavy 1024px People & Faces analysis (lowest background priority)
            if !Task.isCancelled {
                await self.runIdlePeopleAndFacesScan(in: appModel)
            }
        }
    }
    
    /// Executes People & Faces analysis slowly during idle moments when all foreground categories are done.
    private func runIdlePeopleAndFacesScan(in appModel: AppModel) async {
        // Only run if not already completed
        let isDone = await MainActor.run {
            self.isCategoryCompleted(.people, in: appModel)
        }
        guard !isDone else { return }
        
        // Ensure app has been completely idle for at least 800ms before kicking off 1024px Vision work
        try? await Task.sleep(nanoseconds: 800_000_000)
        
        // Cooperative yield check
        while await shouldYield(for: .people) {
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        
        guard !Task.isCancelled else { return }
        await appModel.peopleAndFacesViewModel.executeScan()
    }
    
    private func isCategoryCompleted(_ category: GalleryCategory, in appModel: AppModel) -> Bool {
        switch category {
        case .largeVideos:
            return appModel.largeVideosViewModel.hasLoaded && (appModel.counts[.largeVideos] != nil || !appModel.largeVideosViewModel.sortedLargeVideoAssets.isEmpty)
        case .duplicatePhotos:
            return appModel.duplicatePhotosViewModel.hasCompletedScan && (appModel.counts[.duplicatePhotos] != nil || !appModel.duplicatePhotosViewModel.groups.isEmpty)
        case .duplicateVideos:
            return appModel.duplicateVideosViewModel.hasCompletedScan && (appModel.counts[.duplicateVideos] != nil || !appModel.duplicateVideosViewModel.groups.isEmpty)
        case .blurredPhotos:
            return appModel.blurredPhotosViewModel.hasCompletedScan && (appModel.counts[.blurredPhotos] != nil || !appModel.blurredPhotosViewModel.items.isEmpty)
        case .people:
            return appModel.peopleAndFacesViewModel.hasCompletedScan && (appModel.counts[.people] != nil || !appModel.peopleAndFacesViewModel.items.isEmpty)
        case .similarPhotos:
            return appModel.similarPhotosViewModel.hasCompletedScan && (appModel.counts[.similarPhotos] != nil || !appModel.similarPhotosViewModel.groups.isEmpty)
        default:
            return true
        }
    }
    
    private func runCategoryScan(_ category: GalleryCategory, in appModel: AppModel) async {
        switch category {
        case .largeVideos:
            await appModel.largeVideosViewModel.executeLoad()
        case .duplicatePhotos:
            await appModel.duplicatePhotosViewModel.executeScan()
        case .duplicateVideos:
            await appModel.duplicateVideosViewModel.executeScan()
        case .blurredPhotos:
            await appModel.blurredPhotosViewModel.executeScan()
        case .people:
            await appModel.peopleAndFacesViewModel.executeScan()
        case .similarPhotos:
            await appModel.similarPhotosViewModel.executeScan()
        default:
            break
        }
    }
}
