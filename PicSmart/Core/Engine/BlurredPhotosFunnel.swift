//
//  BlurredPhotosFunnel.swift
//  PicSmart
//

import Foundation
import Photos
import CoreGraphics
import QuartzCore

struct BlurredPhotoItem: Identifiable, Sendable {
    var id: String { asset.localIdentifier }
    let asset: PHAsset
    let sharpnessScore: Double
    let blurPercentage: Int
    let fileSize: Int64
}

actor BlurredPhotosFunnel {
    static let shared = BlurredPhotosFunnel()
    
    /// Calibrated threshold for Laplacian variance below which an image is considered out-of-focus or motion-blurred.
    /// Calibrated for 256px `.highQualityFormat` + `.exact` resize thumbnails analysed with `.high` CGInterpolation.
    /// Sharp iOS photos typically score 600–4000+; truly blurry photos fall below ~300.
    private let blurThreshold: Double = 350.0
    
    private init() {}
    
    /// Evaluates a single newly added asset for incremental delta sync
    func evaluateSingleAsset(_ asset: PHAsset) async -> BlurredPhotoItem? {
        guard let (_, sharpness, dto) = await evaluateAssetSharpness(asset) else { return nil }
        if let dto {
            await FeatureVectorStore.shared.saveSignatures([dto])
        }
        if sharpness < blurThreshold && sharpness >= 0.0 {
            let pct = Int(max(0, min(100, (1.0 - (sharpness / blurThreshold)) * 100)))
            let size = asset.primaryResourceFileSize ?? 3_500_000
            return BlurredPhotoItem(
                asset: asset,
                sharpnessScore: sharpness,
                blurPercentage: pct,
                fileSize: size
            )
        }
        return nil
    }
    
    func scan(progressHandler: (@Sendable (AnalysisProgress) -> Void)? = nil) async -> [BlurredPhotoItem] {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        
        let fetchResult = PHAsset.fetchAssets(with: options)
        let totalCount = fetchResult.count
        guard totalCount > 0 else { return [] }
        
        var allAssets: [PHAsset] = []
        allAssets.reserveCapacity(totalCount)
        fetchResult.enumerateObjects { asset, _, _ in
            allAssets.append(asset)
        }
        
        // 1. Check cached signatures in SwiftData
        let cachedMap = await FeatureVectorStore.shared.loadAllSignatures()
        
        var evaluatedItems: [BlurredPhotoItem] = []
        var missingAssets: [PHAsset] = []
        
        for asset in allAssets {
            if let cached = cachedMap[asset.localIdentifier], cached.sharpnessScore >= 0.0 {
                if cached.sharpnessScore < blurThreshold {
                    let pct = Int(max(0, min(100, (1.0 - (cached.sharpnessScore / blurThreshold)) * 100)))
                    let size = asset.primaryResourceFileSize ?? 3_500_000
                    evaluatedItems.append(BlurredPhotoItem(
                        asset: asset,
                        sharpnessScore: cached.sharpnessScore,
                        blurPercentage: pct,
                        fileSize: size
                    ))
                }
            } else {
                missingAssets.append(asset)
            }
        }
        
        var completedCount = totalCount - missingAssets.count
        var lastProgressTime = CACurrentMediaTime()
        progressHandler?(AnalysisProgress(
            completed: completedCount,
            total: totalCount,
            stage: "Analyzing sharpness (\(completedCount)/\(totalCount))…"
        ))
        
        if !missingAssets.isEmpty {
            let workerCount = 3
            var nextIndex = 0
            var newSignatures: [VisualSignatureDTO] = []
            
            await withTaskGroup(of: (PHAsset, Double, VisualSignatureDTO?)?.self) { group in
                while nextIndex < min(workerCount, missingAssets.count) {
                    let asset = missingAssets[nextIndex]
                    nextIndex += 1
                    group.addTask {
                        await self.evaluateAssetSharpness(asset)
                    }
                }
                
                while let result = await group.next() {
                    if Task.isCancelled { break }
                    completedCount += 1
                    
                    if let (asset, sharpness, dto) = result {
                        if let dto {
                            newSignatures.append(dto)
                        }
                        if sharpness < self.blurThreshold && sharpness >= 0.0 {
                            let pct = Int(max(0, min(100, (1.0 - (sharpness / self.blurThreshold)) * 100)))
                            let size = asset.primaryResourceFileSize ?? 3_500_000
                            evaluatedItems.append(BlurredPhotoItem(
                                asset: asset,
                                sharpnessScore: sharpness,
                                blurPercentage: pct,
                                fileSize: size
                            ))
                        }
                    }
                    
                    let now = CACurrentMediaTime()
                    if now - lastProgressTime >= 0.15 || completedCount == totalCount {
                        lastProgressTime = now
                        progressHandler?(AnalysisProgress(
                            completed: completedCount,
                            total: totalCount,
                            stage: "Analyzing sharpness (\(completedCount)/\(totalCount))…"
                        ))
                    }
                    
                    await AnalysisPipelineCoordinator.shared.yieldIfPreempted(for: .blurredPhotos)
                    if !Task.isCancelled && nextIndex < missingAssets.count {
                        let nextAsset = missingAssets[nextIndex]
                        nextIndex += 1
                        group.addTask {
                            await self.evaluateAssetSharpness(nextAsset)
                        }
                    }
                }
            }
            
            if !newSignatures.isEmpty {
                await FeatureVectorStore.shared.saveSignatures(newSignatures)
            }
        }
        
        // Sort with most blurred (lowest sharpness / highest blur percentage) first
        evaluatedItems.sort { $0.blurPercentage > $1.blurPercentage }
        return evaluatedItems
    }
    
    private func evaluateAssetSharpness(_ asset: PHAsset) async -> (PHAsset, Double, VisualSignatureDTO?)? {
        // Use high-fidelity thumbnail: `.highQualityFormat` + `.exact` resizeMode to avoid JPEG block
        // artifacts from `.fastFormat` that corrupt Laplacian edge measurements.
        guard let cgImage = await ThumbnailService.shared.requestAnalysisThumbnail(for: asset, targetSize: CGSize(width: 256, height: 256)) else {
            return nil
        }

        return autoreleasepool {
            // Use `.high` interpolation quality so Laplacian measures true optical blur, not resampling smoothing
            let sharpness = LaplacianKernel.computeSharpnessVariance(from: cgImage, dimension: 256, interpolationQuality: .high)
            let hashData = DifferenceHash.compute(from: cgImage)

            var dto: VisualSignatureDTO? = nil
            if let hashData {
                dto = VisualSignatureDTO(
                    localIdentifier: asset.localIdentifier,
                    gradientHash: hashData.hash,
                    averageLuminance: hashData.luma,
                    aspectBand: asset.aspectRatioBand,
                    creationWeekBucket: asset.creationWeekBucket,
                    sharpnessScore: sharpness,
                    featureData: nil
                )
            }

            return (asset, sharpness, dto)
        }
    }
}
