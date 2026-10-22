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
    private let blurThreshold: Double = 140.0
    
    private init() {}
    
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
            if let cached = cachedMap[asset.localIdentifier], cached.sharpnessScore > 0 {
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
                        if sharpness < self.blurThreshold && sharpness > 0 {
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
        guard let cgImage = await ThumbnailService.shared.requestFastAnalysisThumbnail(for: asset, targetSize: CGSize(width: 64, height: 64)) else {
            return nil
        }
        
        return autoreleasepool {
            let sharpness = LaplacianKernel.computeSharpnessVariance(from: cgImage, dimension: 64)
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
