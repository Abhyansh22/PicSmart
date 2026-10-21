//
//  ThumbnailService.swift
//  PicSmart
//

import UIKit
import Photos

@MainActor
final class ThumbnailService {
    static let shared = ThumbnailService()
    
    // Dedicated UI caching image manager for grid views and prefetching
    private let uiImageManager = PHCachingImageManager()
    
    // Dedicated background image manager isolated exclusively for offline matrix analysis
    nonisolated private static let analysisImageManager = PHImageManager()
    
    // MARK: - Fast Scanning Thumbnail
    
    /// Requests a fast, local-only 32x32 thumbnail for matrix downsampling and hashing.
    /// Runs synchronously inside background tasks without blocking the UI's caching image manager.
    nonisolated func requestFastAnalysisThumbnail(for asset: PHAsset, targetSize: CGSize = CGSize(width: 32, height: 32)) -> CGImage? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.isNetworkAccessAllowed = false
        options.isSynchronous = true
        options.resizeMode = .fast
        
        var resultImage: CGImage?
        Self.analysisImageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { uiImage, _ in
            resultImage = uiImage?.cgImage
        }
        return resultImage
    }
    
    // MARK: - UI Grid Thumbnail
    
    func requestThumbnail(
        for asset: PHAsset,
        targetSize: CGSize = CGSize(width: 250, height: 250),
        completion: @escaping @Sendable (UIImage?) -> Void
    ) -> PHImageRequestID {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        options.resizeMode = .fast
        
        return uiImageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            completion(image)
        }
    }
    
    func requestFullImage(for asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            
            var resumed = false
            self.uiImageManager.requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                if !resumed {
                    resumed = true
                    continuation.resume(returning: image)
                }
            }
        }
    }
    
    func cancelImageRequest(_ requestID: PHImageRequestID) {
        uiImageManager.cancelImageRequest(requestID)
    }
    
    // MARK: - Prefetching
    
    func startCaching(assets: [PHAsset], targetSize: CGSize = CGSize(width: 250, height: 250)) {
        guard !assets.isEmpty else { return }
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        uiImageManager.startCachingImages(for: assets, targetSize: targetSize, contentMode: .aspectFill, options: options)
    }
    
    func stopCaching(assets: [PHAsset], targetSize: CGSize = CGSize(width: 250, height: 250)) {
        guard !assets.isEmpty else { return }
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        uiImageManager.stopCachingImages(for: assets, targetSize: targetSize, contentMode: .aspectFill, options: options)
    }
    
    func stopAllCaching() {
        uiImageManager.stopCachingImagesForAllAssets()
    }
}
