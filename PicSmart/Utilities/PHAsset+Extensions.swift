//
//  PHAsset+Extensions.swift
//  PicSmart
//

import Photos
import Foundation

extension PHAsset: @retroactive Identifiable {
    public var id: String {
        localIdentifier
    }
}

nonisolated extension PHAsset {
    /// Extracts the file size in bytes from the primary PHAssetResource.
    /// Uses KVC value(forKey: "fileSize") safely.
    var primaryResourceFileSize: Int64? {
        let resources = PHAssetResource.assetResources(for: self)
        let primaryResource = resources.first { res in
            if mediaType == .video {
                return res.type == .video || res.type == .fullSizeVideo
            } else {
                return res.type == .photo || res.type == .fullSizePhoto
            }
        } ?? resources.first
        
        guard let resource = primaryResource else { return nil }
        
        let key = "fileSize"
        guard resource.responds(to: NSSelectorFromString(key)),
              let number = resource.value(forKey: key) as? NSNumber else {
            return nil
        }
        let size = number.int64Value
        return size > 0 ? size : nil
    }
    
    var formattedFileSize: String? {
        guard let bytes = primaryResourceFileSize else { return nil }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
    
    var formattedDuration: String? {
        guard mediaType == .video else { return nil }
        let totalSeconds = Int(duration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var formattedDimensions: String {
        "\(pixelWidth) × \(pixelHeight)"
    }
    
    /// Aspect ratio bucket for structural matching (e.g., Portrait = 1, Square = 2, Landscape = 3)
    var aspectRatioBand: Int {
        guard pixelHeight > 0 else { return 0 }
        let ratio = Double(pixelWidth) / Double(pixelHeight)
        if ratio < 0.85 {
            return 1 // Portrait
        } else if ratio <= 1.15 {
            return 2 // Square
        } else {
            return 3 // Landscape
        }
    }
    
    /// Returns integer week bucket from creation date
    var creationWeekBucket: Int64 {
        guard let date = creationDate else { return 0 }
        return Int64(date.timeIntervalSince1970 / (7 * 24 * 3600))
    }
}
