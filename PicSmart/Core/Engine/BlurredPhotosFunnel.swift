//
//  BlurredPhotosFunnel.swift
//  PicSmart
//

import Foundation
import Photos
import Vision
import CoreGraphics
import QuartzCore

struct BlurredPhotoItem: Identifiable, Sendable {
    var id: String { asset.localIdentifier }
    let asset: PHAsset
    let sharpnessScore: Double
    let blurPercentage: Int
    let fileSize: Int64
    
    var isSevere: Bool {
        blurPercentage >= 75
    }
}

actor BlurredPhotosFunnel {
    static let shared = BlurredPhotosFunnel()
    
    private init() {}
    
    /// Evaluates a single newly added asset for incremental delta sync
    func evaluateSingleAsset(_ asset: PHAsset) async -> BlurredPhotoItem? {
        guard let (_, _, recordDTO, item) = await evaluateAssetSharpness(asset) else { return nil }
        if let recordDTO {
            try? await PersistentClusterStore.shared.saveBlurRecords([recordDTO])
        }
        return item
    }
    
    /// Rapidly hydrates previously verified blurred photos from SwiftData cache without running any Vision models
    func loadCachedBlurredItems() async -> [BlurredPhotoItem] {
        let cachedMap = (try? await PersistentClusterStore.shared.loadAllBlurRecords()) ?? [:]
        let blurredEntries = cachedMap.filter { $0.value.blurPercentage >= 40 }
        guard !blurredEntries.isEmpty else { return [] }
        
        let ids = Array(blurredEntries.keys)
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var assetMap = [String: PHAsset]()
        fetchResult.enumerateObjects { asset, _, _ in
            assetMap[asset.localIdentifier] = asset
        }
        
        var items: [BlurredPhotoItem] = []
        for (id, dto) in blurredEntries {
            guard let asset = assetMap[id] else { continue }
            let size = asset.primaryResourceFileSize ?? 3_500_000
            items.append(BlurredPhotoItem(
                asset: asset,
                sharpnessScore: Double(dto.blurPercentage),
                blurPercentage: dto.blurPercentage,
                fileSize: size
            ))
        }
        items.sort { $0.blurPercentage > $1.blurPercentage }
        return items
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
        
        // 1. Check isolated cached blur records in SwiftData
        let cachedMap = (try? await PersistentClusterStore.shared.loadAllBlurRecords()) ?? [:]
        
        var evaluatedItems: [BlurredPhotoItem] = []
        var missingAssets: [PHAsset] = []
        
        for asset in allAssets {
            if let cached = cachedMap[asset.localIdentifier] {
                if cached.blurPercentage >= 40 {
                    let size = asset.primaryResourceFileSize ?? 3_500_000
                    evaluatedItems.append(BlurredPhotoItem(
                        asset: asset,
                        sharpnessScore: Double(cached.blurPercentage),
                        blurPercentage: cached.blurPercentage,
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
            var pendingFlush: [BlurRecordDTO] = []
            
            await withTaskGroup(of: (PHAsset, Double, BlurRecordDTO?, BlurredPhotoItem?)?.self) { group in
                while nextIndex < min(workerCount, missingAssets.count) {
                    let asset = missingAssets[nextIndex]
                    nextIndex += 1
                    group.addTask {
                        await self.evaluateAssetSharpness(asset)
                    }
                }
                
                while let result = await group.next() {
                    if Task.isCancelled {
                        group.cancelAll()
                        break
                    }
                    completedCount += 1
                    
                    if let (_, _, recordDTO, item) = result {
                        if let recordDTO {
                            pendingFlush.append(recordDTO)
                        }
                        if let item {
                            evaluatedItems.append(item)
                        }
                    }
                    
                    // Periodic Flush every 25 completed items to guarantee in-flight persistence
                    if pendingFlush.count >= 25 {
                        let chunk = pendingFlush
                        pendingFlush.removeAll(keepingCapacity: true)
                        try? await PersistentClusterStore.shared.saveBlurRecords(chunk)
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
                    
                    if Task.isCancelled {
                        group.cancelAll()
                        break
                    }
                    if nextIndex < missingAssets.count {
                        let nextAsset = missingAssets[nextIndex]
                        nextIndex += 1
                        group.addTask {
                            await self.evaluateAssetSharpness(nextAsset)
                        }
                    }
                }
            }
            
            // Flush remaining items (< 25) upon normal completion or cancellation
            if !pendingFlush.isEmpty {
                try? await PersistentClusterStore.shared.saveBlurRecords(pendingFlush)
            }
        }
        
        // Sort with most blurred (highest blur percentage) first
        evaluatedItems.sort { $0.blurPercentage > $1.blurPercentage }
        return evaluatedItems
    }
    
    private func evaluateAssetSharpness(_ asset: PHAsset) async -> (PHAsset, Double, BlurRecordDTO?, BlurredPhotoItem?)? {
        guard !Task.isCancelled else { return nil }
        // Use high-fidelity 1024px thumbnail to preserve optical edge frequencies (eyelashes, hair, texture).
        guard let cgImage = await ThumbnailService.shared.requestAnalysisThumbnail(
            for: asset,
            targetSize: CGSize(width: 1024, height: 1024)
        ) else {
            return nil
        }
        
        return autoreleasepool { () -> (PHAsset, Double, BlurRecordDTO?, BlurredPhotoItem?)? in
            let aestheticsRequest = VNCalculateImageAestheticsScoresRequest()
            let faceRequest = VNDetectFaceCaptureQualityRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
            
            do {
                // Execute bundled Vision pass on Apple Neural Engine in a single hardware invocation
                try handler.perform([aestheticsRequest, faceRequest])
            } catch {
                return nil
            }
            
            // 1. Aesthetics Model Evaluation
            let aestheticObs = aestheticsRequest.results?.first
            let overallAestheticScore = Double(aestheticObs?.overallScore ?? 0.0) // Range: -1.0 to 1.0
            
            // 2. Face Detection & Optical Capture Quality
            let faceResults = faceRequest.results ?? []
            let maxFaceQuality = faceResults.compactMap { $0.faceCaptureQuality.map(Double.init) }.max() ?? 0.0
            let hasFace = !faceResults.isEmpty
            
            // 3. Localized 8x8 Tiled Peak Sharpness (90th percentile)
            let (peakSharpness, _) = LaplacianKernel.computePeakTileSharpnessVariance(
                from: cgImage,
                dimension: 512,
                tileGridSize: 8
            )
            
            // 4. Portrait & Bokeh Whitelist Checks
            let isDepthPhoto = asset.mediaSubtypes.contains(.photoDepthEffect)
            
            // Guard A: Human face is sharp (>= 0.38) -> Whitelist! (Protect portrait with bokeh)
            if hasFace && maxFaceQuality >= 0.38 {
                return makeCleanResult(asset: asset, cgImage: cgImage)
            }
            
            // Guard B: Apple Portrait Mode photo with acceptable subject -> Whitelist!
            if isDepthPhoto && (hasFace ? maxFaceQuality >= 0.28 : overallAestheticScore >= -0.15) {
                return makeCleanResult(asset: asset, cgImage: cgImage)
            }
            
            // Guard C: High aesthetic score with at least one sharp focal tile -> Whitelist! (Protects sunsets, skies, macros)
            if overallAestheticScore >= 0.15 && peakSharpness >= 350.0 {
                return makeCleanResult(asset: asset, cgImage: cgImage)
            }
            
            // 5. Definite Blur Criteria:
            var isBlurred = false
            var blurPercentage = 0
            
            if overallAestheticScore < -0.20 && peakSharpness < 220.0 {
                // Severe camera shake / pocket shot / extreme motion smear
                isBlurred = true
                let normPeak = max(0.0, min(1.0, peakSharpness / 220.0))
                blurPercentage = Int(75.0 + (1.0 - normPeak) * 24.0) // 75% to 99%
            } else if overallAestheticScore < 0.05 && peakSharpness < 350.0 {
                // Soft focus / low optical clarity
                isBlurred = true
                let normPeak = max(0.0, min(1.0, peakSharpness / 350.0))
                blurPercentage = Int(40.0 + (1.0 - normPeak) * 34.0) // 40% to 74%
            }
            
            let size = asset.primaryResourceFileSize ?? 3_500_000
            let recordDTO = BlurRecordDTO(
                localIdentifier: asset.localIdentifier,
                blurPercentage: isBlurred ? blurPercentage : 0,
                isSevere: blurPercentage >= 75,
                evaluatedAt: Date(),
                modificationTime: asset.modificationDate?.timeIntervalSince1970 ?? 0
            )
            
            let item: BlurredPhotoItem? = isBlurred ? BlurredPhotoItem(
                asset: asset,
                sharpnessScore: peakSharpness,
                blurPercentage: blurPercentage,
                fileSize: size
            ) : nil
            
            return (asset, isBlurred ? Double(blurPercentage) : 0.0, recordDTO, item)
        }
    }
    
    private func makeCleanResult(
        asset: PHAsset,
        cgImage: CGImage
    ) -> (PHAsset, Double, BlurRecordDTO?, BlurredPhotoItem?) {
        let recordDTO = BlurRecordDTO(
            localIdentifier: asset.localIdentifier,
            blurPercentage: 0,
            isSevere: false,
            evaluatedAt: Date(),
            modificationTime: asset.modificationDate?.timeIntervalSince1970 ?? 0
        )
        return (asset, 0.0, recordDTO, nil)
    }
}
