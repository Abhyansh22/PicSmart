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

    /// Requests a fast, local-only thumbnail for matrix downsampling and hashing asynchronously.
    /// Uses `.fastFormat` + `.fast` resizeMode for speed-critical hash/similarity scans at small sizes.
    nonisolated func requestFastAnalysisThumbnail(for asset: PHAsset, targetSize: CGSize = CGSize(width: 32, height: 32)) async -> CGImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .fastFormat
            options.isNetworkAccessAllowed = false
            options.isSynchronous = false
            options.resizeMode = .fast

            var didResume = false
            Self.analysisImageManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { uiImage, _ in
                if !didResume {
                    didResume = true
                    continuation.resume(returning: uiImage?.cgImage)
                }
            }
        }
    }

    // MARK: - High-Fidelity Analysis Thumbnail

    /// Requests a higher-fidelity thumbnail for signal-sensitive analysis (blur detection, face landmark detection).
    /// Uses `.opportunistic` delivery + `.exact` resize to preserve edges and avoid JPEG compression artifacts
    /// that would otherwise corrupt Laplacian/landmark measurements.
    /// Falls back to `.fastFormat` result if PhotoKit cannot deliver `.highQualityFormat`.
    nonisolated func requestAnalysisThumbnail(for asset: PHAsset, targetSize: CGSize) async -> CGImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = false
            options.isSynchronous = false
            options.resizeMode = .exact

            var didResume = false
            Self.analysisImageManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { uiImage, info in
                // Skip degraded intermediate deliveries; wait for the final high-quality callback
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                guard !isDegraded else { return }
                if !didResume {
                    didResume = true
                    continuation.resume(returning: uiImage?.cgImage)
                }
            }
        }
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
    
    // MARK: - Progressive High-Resolution Image Loading
    
    /// Requests a full-resolution asset with progressive two-tier loading and protection against the degraded image trap.
    /// 1. Immediately renders an instant medium-sized preview (~520px) if onPreview is provided so the screen is never blank.
    /// 2. Asynchronously requests the true full-resolution asset, waiting for the non-degraded callback before resuming.
    func requestFullImage(
        for asset: PHAsset,
        onPreview: (@Sendable (UIImage) -> Void)? = nil
    ) async -> UIImage? {
        // Tier 1: Instant ~520px preview thumbnail
        if let onPreview {
            let previewOptions = PHImageRequestOptions()
            previewOptions.deliveryMode = .fastFormat
            previewOptions.isNetworkAccessAllowed = true
            previewOptions.resizeMode = .fast
            
            _ = uiImageManager.requestImage(
                for: asset,
                targetSize: CGSize(width: 520, height: 520),
                contentMode: .aspectFit,
                options: previewOptions
            ) { previewImage, _ in
                if let previewImage {
                    onPreview(previewImage)
                }
            }
        }
        
        // Tier 2: True full-resolution image with degraded callback guard
        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.resizeMode = .exact
            
            var temporaryImage: UIImage?
            var didResume = false
            
            self.uiImageManager.requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                let isCancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                let error = info?[PHImageErrorKey] as? Error
                
                // If degraded and no error, offer as temporary preview and wait for the true high-res callback
                if isDegraded && error == nil && !isCancelled {
                    if let image {
                        temporaryImage = image
                        onPreview?(image)
                    }
                    return // Wait for the high-res callback
                }
                
                if !didResume {
                    didResume = true
                    // Return final high-res image, or fallback to temporary image if available
                    continuation.resume(returning: image ?? temporaryImage)
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
