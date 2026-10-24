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
    
    // MARK: - High-Resolution Face Avatar Request

    /// Requests a crisp face avatar thumbnail using face-proportional scaling.
    /// Calculates the source thumbnail size such that the cropped face region yields at least 300px
    /// of raw pixel detail, eliminating pixelation while avoiding decoding 48MP raw images.
    /// Returns immediately via onPreview if a fast lower-res crop is available.
    func requestFaceAvatar(
        for asset: PHAsset,
        faceBoundingBox: CGRect,
        displaySize: CGFloat,
        onPreview: (@Sendable (UIImage) -> Void)? = nil
    ) async -> UIImage? {
        let cacheKey = FaceAvatarCache.shared.key(
            assetIdentifier: asset.localIdentifier,
            boundingBox: faceBoundingBox,
            size: displaySize
        )
        
        // 1. Synchronous Memory Cache Hit
        if let cached = FaceAvatarCache.shared.get(key: cacheKey) {
            return cached
        }
        
        // 2. Calculate Face-Proportional Resolution
        // Ensure the cropped face has ~300-360px for tack-sharp Retina display.
        let faceFraction = max(CGFloat(faceBoundingBox.size.width), 0.12)
        let desiredFacePixels = max(displaySize * 2.5, 300.0)
        let calculatedDim = desiredFacePixels / faceFraction
        // Clamp between 800px and 1600px to ensure PhotoKit serves precomputed cache derivatives
        let targetDimension = min(1600.0, max(800.0, calculatedDim))
        let targetSize = CGSize(width: targetDimension, height: targetDimension)
        
        // 3. Fast Tier 1 Preview
        if let onPreview {
            let previewOptions = PHImageRequestOptions()
            previewOptions.deliveryMode = .fastFormat
            previewOptions.isNetworkAccessAllowed = false
            previewOptions.resizeMode = .fast
            
            _ = uiImageManager.requestImage(
                for: asset,
                targetSize: CGSize(width: 400, height: 400),
                contentMode: .aspectFit,
                options: previewOptions
            ) { previewImage, _ in
                if let previewImage, let cropped = Self.cropFace(from: previewImage, faceBoundingBox: faceBoundingBox) {
                    onPreview(cropped)
                }
            }
        }
        
        // 4. High-Fidelity Tier 2
        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.isNetworkAccessAllowed = true
            options.resizeMode = .fast
            
            var didResume = false
            var fallbackImage: UIImage?
            
            self.uiImageManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                let isCancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                let error = info?[PHImageErrorKey] as? Error
                
                guard !isCancelled, error == nil, let image else {
                    if !didResume {
                        didResume = true
                        continuation.resume(returning: fallbackImage)
                    }
                    return
                }
                
                if let cropped = Self.cropFace(from: image, faceBoundingBox: faceBoundingBox) {
                    if isDegraded {
                        fallbackImage = cropped
                        onPreview?(cropped)
                    } else {
                        FaceAvatarCache.shared.set(key: cacheKey, image: cropped)
                        if !didResume {
                            didResume = true
                            continuation.resume(returning: cropped)
                        }
                    }
                } else if !didResume {
                    didResume = true
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    /// Crops a face bounding box with natural 1.5x portrait framing and upper-center bias
    nonisolated static func cropFace(
        from sourceImage: UIImage,
        faceBoundingBox: CGRect
    ) -> UIImage? {
        guard let cgImage = sourceImage.cgImage else { return nil }
        let imgW = CGFloat(cgImage.width)
        let imgH = CGFloat(cgImage.height)
        guard imgW > 0, imgH > 0 else { return nil }
        
        // Vision boundingBox has (0,0) at bottom-left
        let x = faceBoundingBox.origin.x * imgW
        let y = (1.0 - faceBoundingBox.origin.y - faceBoundingBox.size.height) * imgH
        let w = faceBoundingBox.size.width * imgW
        let h = faceBoundingBox.size.height * imgH
        
        // Portrait framing: 1.50x box, biased 45% towards forehead so hair isn't cut
        let side = max(w, h) * 1.50
        let centerX = x + w * 0.5
        let centerY = y + h * 0.45
        
        let cropX = max(0, min(imgW - side, centerX - side * 0.5))
        let cropY = max(0, min(imgH - side, centerY - side * 0.5))
        let cropRect = CGRect(
            x: cropX,
            y: cropY,
            width: min(side, imgW - cropX),
            height: min(side, imgH - cropY)
        )
        
        guard let croppedCG = cgImage.cropping(to: cropRect) else { return nil }
        
        // Draw into square 300x300 canvas to flatten orientation and optimize memory
        let targetSize = CGSize(width: 300, height: 300)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            let orientedImage = UIImage(cgImage: croppedCG, scale: 1.0, orientation: sourceImage.imageOrientation)
            orientedImage.draw(in: CGRect(origin: .zero, size: targetSize))
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
