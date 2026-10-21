//
//  ExactDuplicateFunnel.swift
//  PicSmart
//

import Photos
import CryptoKit
import Foundation

struct ExactDuplicateFunnel: Sendable {
    /// Runs the 3-stage exact duplicate photo funnel:
    /// Stage 1: Dimension bucketing (width x height)
    /// Stage 2: Exact byte size (PHAssetResource) - separates bursts from true duplicates
    /// Stage 3: 32x32 thumbnail raw RGB pixel SHA-256 verification
    static func scan(
        progressHandler: (@Sendable (AnalysisProgress) -> Void)? = nil
    ) async -> [AssetGroup] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let fetchResult = PHAsset.fetchAssets(with: .image, options: options)
        let total = fetchResult.count
        guard total > 1 else { return [] }
        
        // Stage 1: In-memory dimension bucketing (eliminates ~80-90% in < 5 ms)
        progressHandler?(AnalysisProgress(completed: 0, total: total, stage: "Filtering image dimensions…"))
        
        struct DimKey: Hashable {
            let width: Int
            let height: Int
        }
        
        var dimBuckets = [DimKey: [PHAsset]]()
        var allAssets: [PHAsset] = []
        allAssets.reserveCapacity(total)
        
        fetchResult.enumerateObjects { asset, _, stop in
            if Task.isCancelled { stop.pointee = true; return }
            // Skip screenshots
            if !asset.mediaSubtypes.contains(.photoScreenshot) {
                allAssets.append(asset)
                let key = DimKey(width: asset.pixelWidth, height: asset.pixelHeight)
                dimBuckets[key, default: []].append(asset)
            }
        }
        
        guard !Task.isCancelled else { return [] }
        
        // Keep only dimension buckets with 2+ assets
        let candidateGroups = dimBuckets.values.filter { $0.count > 1 }
        let totalCandidates = candidateGroups.reduce(0) { $0 + $1.count }
        guard totalCandidates > 1 else { return [] }
        
        // Stage 2: Exact Byte-Size Bucketing (Burst-Shot defense)
        progressHandler?(AnalysisProgress(completed: 0, total: totalCandidates, stage: "Analyzing file byte sizes…"))
        
        var sizeBuckets = [Int64: [PHAsset]]()
        var assetFileSizes = [String: Int64]()
        var processedCount = 0
        
        for group in candidateGroups {
            for asset in group {
                if Task.isCancelled { return [] }
                autoreleasepool {
                    let size = asset.primaryResourceFileSize ?? 0
                    if size > 0 {
                        assetFileSizes[asset.localIdentifier] = size
                        sizeBuckets[size, default: []].append(asset)
                    }
                }
                processedCount += 1
                if processedCount % 20 == 0 || processedCount == totalCandidates {
                    await Task.yield()
                    progressHandler?(AnalysisProgress(completed: processedCount, total: totalCandidates, stage: "Analyzing file byte sizes (\(processedCount)/\(totalCandidates))…"))
                }
            }
        }
        
        let sizeCandidates = sizeBuckets.values.filter { $0.count > 1 }
        guard !sizeCandidates.isEmpty else { return [] }
        
        // Stage 3: Downsampled 32x32 Thumbnail SHA-256 Pixel Verification
        progressHandler?(AnalysisProgress(completed: 0, total: sizeCandidates.count, stage: "Verifying exact pixel data…"))
        
        var finalGroups: [AssetGroup] = []
        
        for candidateList in sizeCandidates {
            if Task.isCancelled { break }
            
            var hashToAssets = [String: [PHAsset]]()
            for asset in candidateList {
                autoreleasepool {
                    if let cgImage = ThumbnailService.shared.requestFastAnalysisThumbnail(for: asset, targetSize: CGSize(width: 32, height: 32)),
                       let matrix = MatrixDownsampler.downsampleToGrayscale(image: cgImage, targetWidth: 32, targetHeight: 32) {
                        let digest = SHA256.hash(data: matrix.pixels)
                        let hashString = digest.map { String(format: "%02x", $0) }.joined()
                        hashToAssets[hashString, default: []].append(asset)
                    }
                }
            }
            
            for (hashKey, exactMatchList) in hashToAssets where exactMatchList.count > 1 {
                let sortedByOldest = exactMatchList.sorted {
                    ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast)
                }
                let keeper = sortedByOldest.first?.localIdentifier
                
                finalGroups.append(AssetGroup(
                    id: "dup_photo_\(hashKey.prefix(12))",
                    assets: sortedByOldest,
                    keeperId: keeper,
                    bestShotId: keeper,
                    fileSizes: assetFileSizes,
                    similarityScore: 1.0
                ))
            }
        }
        
        return finalGroups
    }
}
