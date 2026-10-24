//
//  FaceAvatarCache.swift
//  PicSmart
//

import UIKit

/// In-memory cache for cropped face avatar images.
/// Ensures zero-latency synchronous retrieval when scrolling face grids, eliminating frame drops and re-cropping.
final class FaceAvatarCache: @unchecked Sendable {
    static let shared = FaceAvatarCache()
    
    private let cache = NSCache<NSString, UIImage>()
    
    private init() {
        cache.countLimit = 250
        cache.totalCostLimit = 60 * 1024 * 1024 // 60 MB maximum cache size
    }
    
    func key(assetIdentifier: String, boundingBox: CGRect, size: CGFloat) -> String {
        let x = Int(boundingBox.origin.x * 1000)
        let y = Int(boundingBox.origin.y * 1000)
        let w = Int(boundingBox.size.width * 1000)
        let s = Int(size)
        return "\(assetIdentifier)_\(x)_\(y)_\(w)_\(s)"
    }
    
    func get(key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }
    
    func set(key: String, image: UIImage) {
        let cost = Int(image.size.width * image.size.height * 4)
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }
    
    func clear() {
        cache.removeAllObjects()
    }
}
