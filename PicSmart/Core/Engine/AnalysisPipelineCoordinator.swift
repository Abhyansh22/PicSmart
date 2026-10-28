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

/// Central coordinator managing the 2-Space Window Priority Scheduler:
/// Slot 1: Active user target (runs to 100% completion even when navigating back to Home)
/// Slot 2: Interrupted target (preempted work saved at checkpoint, resumes when Slot 1 finishes)
/// Sequential Queue: Baseline sequence for uncompleted categories when Slots 1 & 2 are clear.
@Observable
@MainActor
final class AnalysisPipelineCoordinator {
    static let shared = AnalysisPipelineCoordinator()
    
    // MARK: - 2-Space Window Scheduling State
    
    /// Slot 1: The current primary execution target.
    private(set) var slot1ActiveCategory: GalleryCategory?
    
    /// Slot 2: The category interrupted by the user, waiting to resume at its checkpoint.
    private(set) var slot2InterruptedCategory: GalleryCategory?
    
    /// Resilient stack of interrupted categories in LIFO order to guarantee no category is ever forgotten
    private(set) var interruptedStack: [GalleryCategory] = []
    
    /// The category screen currently displayed in the foreground (nil if on HomeView).
    private(set) var foregroundScreenCategory: GalleryCategory?
    
    /// Returns the active category for backward-compatible view checks.
    var activeCategory: GalleryCategory? {
        get { foregroundScreenCategory ?? slot1ActiveCategory }
        set { foregroundScreenCategory = newValue }
    }
    
    @ObservationIgnored
    private(set) var isSuspendedForBackground: Bool = false
    
    @ObservationIgnored
    private var schedulerTask: Task<Void, Never>?
    
    /// Baseline order of background analysis based on computational complexity:
    @ObservationIgnored
    private let backgroundSequence: [GalleryCategory] = [
        .largeVideos,
        .duplicatePhotos,
        .duplicateVideos,
        .blurredPhotos,
        .similarPhotos,
        .people
    ]
    
    private init() {}
    
    // MARK: - Priority Management (2-Space Window Handshake)
    
    /// Called when the user navigates into a category screen.
    func elevatePriority(for category: GalleryCategory, in appModel: AppModel? = nil) {
        foregroundScreenCategory = category
        
        guard let appModel else { return }
        
        // If another category is currently executing in Slot 1 and is NOT this category:
        if let currentS1 = slot1ActiveCategory, currentS1 != category {
            // Cancel current S1 cleanly (Option 2: Clean Task Cancellation)
            cancelCategoryTask(currentS1, in: appModel)
            
            // Push current Slot 2 to stack if valid and not redundant
            if let existingS2 = slot2InterruptedCategory, existingS2 != currentS1 && existingS2 != category {
                if !interruptedStack.contains(existingS2) {
                    interruptedStack.append(existingS2)
                }
            }
            slot2InterruptedCategory = currentS1
            interruptedStack.removeAll(where: { $0 == currentS1 || $0 == category })
        }
        
        // Slot 1 is now the user's active intent
        slot1ActiveCategory = category
        
        // Ensure scheduler is active
        startProactiveBackgroundScan(appModel: appModel)
        
        // Launch Category scan immediately
        triggerCategoryScan(category, in: appModel)
    }
    
    /// Called when the user leaves the category screen.
    func releasePriority(for category: GalleryCategory) {
        if foregroundScreenCategory == category {
            foregroundScreenCategory = nil
        }
        // Anti-Thrashing: Slot 1 REMAINS category!
        // It continues executing in the background until 100% complete,
        // and then the scheduler automatically awakens Slot 2 or continues the baseline queue.
    }
    
    // MARK: - Background Lifecycle Management
    
    /// Suspends background workers when app transitions to .background
    func suspendForBackground() {
        isSuspendedForBackground = true
    }
    
    /// Resumes background workers when app returns to .active
    func resumeFromBackground() {
        isSuspendedForBackground = false
    }
    
    /// Checks if a category should cooperatively yield its CPU/worker slots.
    nonisolated func shouldYield(for category: GalleryCategory) async -> Bool {
        let (s1, isSuspended) = await MainActor.run { (self.slot1ActiveCategory, self.isSuspendedForBackground) }
        if isSuspended { return true }
        guard let s1 else { return false }
        return s1 != category
    }
    
    /// Cooperatively pauses if preempted by another slot.
    nonisolated func yieldIfPreempted(for category: GalleryCategory) async {
        while await shouldYield(for: category) {
            try? await Task.sleep(nanoseconds: 150_000_000) // 150ms cooperative wait
        }
        
        // Cooperative pacing when on Home screen (foregroundScreenCategory == nil)
        let foreground = await MainActor.run { self.foregroundScreenCategory }
        if foreground == nil {
            try? await Task.sleep(nanoseconds: 20_000_000) // 20ms pacing for 120 FPS UI
        }
    }
    
    // MARK: - Cancellation
    
    func cancel() {
        schedulerTask?.cancel()
        schedulerTask = nil
        slot1ActiveCategory = nil
        slot2InterruptedCategory = nil
        interruptedStack.removeAll()
        foregroundScreenCategory = nil
    }
    
    // MARK: - Proactive 2-Space Scheduler Loop
    
    /// Starts the 2-Space Window Priority Scheduler.
    func startProactiveBackgroundScan(appModel: AppModel, force: Bool = false) {
        if force {
            schedulerTask?.cancel()
            schedulerTask = nil
        }
        guard schedulerTask == nil else { return }
        
        let status = PhotoLibraryService.shared.authorizationStatus
        guard status == .authorized || status == .limited else {
            return
        }
        
        schedulerTask = Task.detached(priority: .utility) { [weak self, weak appModel] in
            guard let self, let appModel else { return }
            
            // Allow initial cold launch render & scroll to settle (1000ms delay)
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            
            await self.runSchedulerLoop(appModel: appModel)
            
            await MainActor.run {
                self.schedulerTask = nil
            }
        }
    }
    
    /// The core 2-space scheduling loop enforcing the Single-Worker Priority Lock.
    private func runSchedulerLoop(appModel: AppModel) async {
        while !Task.isCancelled {
            // 1. Wait if suspended for background
            while isSuspendedForBackground {
                try? await Task.sleep(nanoseconds: 200_000_000)
                if Task.isCancelled { return }
            }
            
            // 2. Resolve next category to execute:
            let categoryToRun: GalleryCategory
            
            let (s1, s2) = await MainActor.run { (self.slot1ActiveCategory, self.slot2InterruptedCategory) }
            
            if let s1, await MainActor.run(body: { !self.isCategoryCompleted(s1, in: appModel) }) {
                // Slot 1 (Active User Intent) runs until 100% complete
                categoryToRun = s1
            } else if let s2, await MainActor.run(body: { !self.isCategoryCompleted(s2, in: appModel) }) {
                // Slot 2 (Interrupted Target) resumes at its checkpoint
                await MainActor.run {
                    self.slot1ActiveCategory = s2
                    self.slot2InterruptedCategory = nil
                }
                categoryToRun = s2
            } else if let nextInterrupted = await MainActor.run(body: {
                self.interruptedStack.first(where: { !self.isCategoryCompleted($0, in: appModel) })
            }) {
                // Resume previous interrupted categories in LIFO stack order
                await MainActor.run {
                    self.interruptedStack.removeAll(where: { $0 == nextInterrupted })
                    self.slot1ActiveCategory = nextInterrupted
                }
                categoryToRun = nextInterrupted
            } else {
                // Clear completed slots
                await MainActor.run {
                    self.slot1ActiveCategory = nil
                    self.slot2InterruptedCategory = nil
                    self.interruptedStack.removeAll()
                }
                
                // Fallback to baseline sequential queue for any incomplete categories
                let nextIncomplete = await MainActor.run {
                    self.backgroundSequence.first(where: { !self.isCategoryCompleted($0, in: appModel) })
                }
                
                guard let next = nextIncomplete else {
                    // All categories 100% complete across the library!
                    break
                }
                
                await MainActor.run {
                    self.slot1ActiveCategory = next
                }
                categoryToRun = next
            }
            
            // 3. Execute the single active category to completion
            await runCategoryScan(categoryToRun, in: appModel)
            
            // 4. Mark Slot 1 clear if completed
            await MainActor.run {
                if self.isCategoryCompleted(categoryToRun, in: appModel) {
                    if self.slot1ActiveCategory == categoryToRun {
                        self.slot1ActiveCategory = nil
                    }
                    if self.slot2InterruptedCategory == categoryToRun {
                        self.slot2InterruptedCategory = nil
                    }
                    self.interruptedStack.removeAll(where: { $0 == categoryToRun })
                }
            }
            
            // Cooperative pause between category transitions
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
    }
    
    private func triggerCategoryScan(_ category: GalleryCategory, in appModel: AppModel) {
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
    
    private func cancelCategoryTask(_ category: GalleryCategory, in appModel: AppModel) {
        switch category {
        case .duplicatePhotos:
            appModel.duplicatePhotosViewModel.cancel()
        case .duplicateVideos:
            appModel.duplicateVideosViewModel.cancel()
        case .similarPhotos:
            appModel.similarPhotosViewModel.cancel()
        case .largeVideos:
            appModel.largeVideosViewModel.cancel()
        case .blurredPhotos:
            appModel.blurredPhotosViewModel.cancel()
        case .people:
            appModel.peopleAndFacesViewModel.cancel()
        default:
            break
        }
    }
    
    func isCategoryCompleted(_ category: GalleryCategory, in appModel: AppModel) -> Bool {
        switch category {
        case .screenshots:
            return appModel.screenshotsViewModel.hasLoaded || appModel.counts[.screenshots] != nil
        case .videos:
            return appModel.videosViewModel.hasLoaded || appModel.counts[.videos] != nil
        case .largeVideos:
            return appModel.largeVideosViewModel.hasLoaded
        case .duplicatePhotos:
            return appModel.duplicatePhotosViewModel.hasCompletedScan
        case .duplicateVideos:
            return appModel.duplicateVideosViewModel.hasCompletedScan
        case .blurredPhotos:
            return appModel.blurredPhotosViewModel.hasCompletedScan
        case .people:
            return appModel.peopleAndFacesViewModel.hasCompletedScan
        case .similarPhotos:
            return appModel.similarPhotosViewModel.hasCompletedScan
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
        case .similarPhotos:
            await appModel.similarPhotosViewModel.executeScan()
        case .people:
            await appModel.peopleAndFacesViewModel.executeScan()
        default:
            break
        }
    }
}
