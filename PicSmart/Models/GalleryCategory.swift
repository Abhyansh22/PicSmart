//
//  GalleryCategory.swift
//  PicSmart
//

import SwiftUI

enum CategorySection: String, CaseIterable, Identifiable {
    case cleanUp = "Clean Up Recommendations"
    case organize = "Organize & Review"
    
    var id: String { rawValue }
}

enum GalleryCategory: String, CaseIterable, Identifiable, Hashable, Sendable {
    // Clean Up Section
    case similarPhotos
    case duplicatePhotos
    case blurredPhotos
    case largeVideos
    case duplicateVideos
    
    // Organize & Review Section
    case people
    case screenshots
    case videos
    
    var id: String { rawValue }
    
    var section: CategorySection {
        switch self {
        case .similarPhotos, .duplicatePhotos, .blurredPhotos, .largeVideos, .duplicateVideos:
            return .cleanUp
        case .people, .screenshots, .videos:
            return .organize
        }
    }
    
    var title: String {
        switch self {
        case .screenshots: return "Screenshots"
        case .videos: return "Videos"
        case .duplicatePhotos: return "Duplicate Photos"
        case .similarPhotos: return "Similar Photos"
        case .duplicateVideos: return "Duplicate Videos"
        case .largeVideos: return "Large Videos"
        case .blurredPhotos: return "Blurred Photos"
        case .people: return "People & Faces"
        }
    }
    
    var subtitle: String {
        switch self {
        case .screenshots: return "All captured screens"
        case .videos: return "Full video library"
        case .duplicatePhotos: return "Exact photo copies"
        case .similarPhotos: return "Visually resembling shots"
        case .duplicateVideos: return "Exact video duplicates"
        case .largeVideos: return "Heavy storage consumers"
        case .blurredPhotos: return "Out-of-focus & shaky shots"
        case .people: return "Portraits & face shots"
        }
    }
    
    var iconName: String {
        switch self {
        case .screenshots: return "camera.viewfinder"
        case .videos: return "video.fill"
        case .duplicatePhotos: return "doc.on.doc.fill"
        case .similarPhotos: return "photo.stack.fill"
        case .duplicateVideos: return "film.stack.fill"
        case .largeVideos: return "arrow.down.circle.fill"
        case .blurredPhotos: return "viewfinder.trianglebadge.exclamationmark"
        case .people: return "person.2.fill"
        }
    }
    
    var themeColor: Color {
        switch self {
        case .screenshots: return Color(red: 0.20, green: 0.50, blue: 1.0)
        case .videos: return Color(red: 0.65, green: 0.35, blue: 0.95)
        case .duplicatePhotos: return Color(red: 1.0, green: 0.58, blue: 0.0)
        case .similarPhotos: return Color(red: 0.95, green: 0.30, blue: 0.50)
        case .duplicateVideos: return Color(red: 0.35, green: 0.45, blue: 0.95)
        case .largeVideos: return Color(red: 0.92, green: 0.26, blue: 0.26)
        case .blurredPhotos: return Color(red: 0.90, green: 0.45, blue: 0.15)
        case .people: return Color(red: 0.15, green: 0.70, blue: 0.75)
        }
    }
    
    var isGrouped: Bool {
        switch self {
        case .duplicatePhotos, .similarPhotos, .duplicateVideos:
            return true
        case .screenshots, .videos, .largeVideos, .blurredPhotos, .people:
            return false
        }
    }
}

/// Single, unambiguous lifecycle state for any category in PicSmart.
public enum CategoryStatus: Equatable, Sendable {
    /// Analysis has not been started yet.
    case notStarted
    
    /// Actively analyzing media with progress percentage and human-readable stage.
    case analyzing(progress: Double, stage: String, completed: Int, total: Int)
    
    /// Interrupted by user preemption or app suspension. Checkpointed at N items.
    case paused(completed: Int, total: Int)
    
    /// 100% of assets in the library have been fully evaluated.
    case completed(count: Int)
    
    public var isCompleted: Bool {
        if case .completed = self { return true }
        return false
    }
    
    public var isAnalyzing: Bool {
        if case .analyzing = self { return true }
        return false
    }
    
    public var isPaused: Bool {
        if case .paused = self { return true }
        return false
    }
    
    public var count: Int? {
        switch self {
        case .completed(let count): return count
        case .paused(let completed, _): return completed > 0 ? completed : nil
        case .analyzing(_, _, let completed, _): return completed > 0 ? completed : nil
        case .notStarted: return nil
        }
    }
}
