//
//  GalleryCategory.swift
//  PicSmart
//

import SwiftUI

enum GalleryCategory: String, CaseIterable, Identifiable, Hashable, Sendable {
    case screenshots
    case videos
    case duplicatePhotos
    case similarPhotos
    case duplicateVideos
    case largeVideos
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .screenshots: return "Screenshots"
        case .videos: return "Videos"
        case .duplicatePhotos: return "Duplicate Photos"
        case .similarPhotos: return "Similar Photos"
        case .duplicateVideos: return "Duplicate Videos"
        case .largeVideos: return "Large Videos"
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
        }
    }
    
    var isGrouped: Bool {
        switch self {
        case .duplicatePhotos, .similarPhotos, .duplicateVideos:
            return true
        case .screenshots, .videos, .largeVideos:
            return false
        }
    }
}
