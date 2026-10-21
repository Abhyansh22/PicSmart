//
//  ThumbnailService.swift
//  PicSmart
//

import UIKit
import Photos

@MainActor
final class ThumbnailService {
    static let shared = ThumbnailService()
    
    private let imageManager = PHCachingImageManager()
    
    // MARK: - Fast Scanning Thumbnail
    
    /// Requests a fast, local-only 32x32 thumbnail for matrix downsampling and hashing.
    /// Runs synchronously inside background tasks without blocking on network.
    nonisolated func requestFastAnalysisThumbnail(for asset: PHAsset, targetSize: CGSize = CGSize(width: 32, height: 32)) -> CGImage? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.isNetworkAccessAllowed = false
        options.isSynchronous = true
        options.resizeMode = .fast
        
        var resultImage: CGImage?
        imageManager.requestImage(
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
        
        return imageManager.requestImage(
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
            self.imageManager.requestImage(
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
        imageManager.cancelImageRequest(requestID)
    }
    
    // MARK: - Prefetching
    
    func startCaching(assets: [PHAsset], targetSize: CGSize = CGSize(width: 250, height: 250)) {
        guard !assets.isEmpty else { return }
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        imageManager.startCachingImages(for: assets, targetSize: targetSize, contentMode: .aspectFill, options: options)
    }
    
    func stopCaching(assets: [PHAsset], targetSize: CGSize = CGSize(width: 250, height: 250)) {
        guard !assets.isEmpty else { return }
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        imageManager.stopCachingImages(for: assets, targetSize: targetSize, contentMode: .aspectFill, options: options)
    }
    
    func stopAllCaching() {
        imageManager.stopCachingImagesForAllAssets()
    }
}
