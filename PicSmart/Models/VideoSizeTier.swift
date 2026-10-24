//
//  VideoSizeTier.swift
//  PicSmart
//

import Foundation
import Photos

/// Size-based segregation brackets for the Large Videos category.
/// Modeled after Apple Photos temporal sections (Years / Months / Days),
/// organizing videos into descending size tiers.
enum VideoSizeTier: Int, CaseIterable, Comparable, Identifiable, Sendable {
    case tenGigabytesAndMore = 5
    case oneToTenGigabytes = 4
    case fiveHundredToOneGigabyte = 3
    case twoFiftyToFiveHundredMB = 2
    case oneHundredToTwoFiftyMB = 1
    case underOneHundredMB = 0
    
    var id: Int { rawValue }
    
    var title: String {
        switch self {
        case .tenGigabytesAndMore: return "10 GB & More"
        case .oneToTenGigabytes: return "1 GB – 10 GB"
        case .fiveHundredToOneGigabyte: return "500 MB – 1 GB"
        case .twoFiftyToFiveHundredMB: return "250 MB – 500 MB"
        case .oneHundredToTwoFiftyMB: return "100 MB – 250 MB"
        case .underOneHundredMB: return "Under 100 MB"
        }
    }
    
    var subtitle: String {
        switch self {
        case .tenGigabytesAndMore: return "Massive media files"
        case .oneToTenGigabytes: return "Multi-gigabyte video files"
        case .fiveHundredToOneGigabyte: return "500 MB to 1 GB files"
        case .twoFiftyToFiveHundredMB: return "250 MB to 500 MB files"
        case .oneHundredToTwoFiftyMB: return "100 MB to 250 MB files"
        case .underOneHundredMB: return "Smaller video files"
        }
    }
    
    var iconName: String {
        switch self {
        case .tenGigabytesAndMore: return "externaldrive.badge.exclamationmark"
        case .oneToTenGigabytes: return "externaldrive.fill"
        case .fiveHundredToOneGigabyte: return "film.stack.fill"
        case .twoFiftyToFiveHundredMB: return "film.fill"
        case .oneHundredToTwoFiftyMB: return "video.fill"
        case .underOneHundredMB: return "play.rectangle.fill"
        }
    }
    
    static let oneMB: Int64 = 1024 * 1024
    static let oneGB: Int64 = 1024 * 1024 * 1024
    
    static func tier(for bytes: Int64) -> VideoSizeTier {
        let tenGB: Int64 = 10 * oneGB
        let oneGB: Int64 = Self.oneGB
        let fiveHundredMB: Int64 = 500 * oneMB
        let twoFiftyMB: Int64 = 250 * oneMB
        let oneHundredMB: Int64 = 100 * oneMB
        
        if bytes >= tenGB {
            return .tenGigabytesAndMore
        } else if bytes >= oneGB {
            return .oneToTenGigabytes
        } else if bytes >= fiveHundredMB {
            return .fiveHundredToOneGigabyte
        } else if bytes >= twoFiftyMB {
            return .twoFiftyToFiveHundredMB
        } else if bytes >= oneHundredMB {
            return .oneHundredToTwoFiftyMB
        } else {
            return .underOneHundredMB
        }
    }
    
    static func < (lhs: VideoSizeTier, rhs: VideoSizeTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A grouped section of videos within a specific size bracket.
struct VideoSizeSection: Identifiable, Sendable {
    let tier: VideoSizeTier
    let assets: [PHAsset]
    let totalBytes: Int64
    
    var id: VideoSizeTier { tier }
    var title: String { tier.title }
}
