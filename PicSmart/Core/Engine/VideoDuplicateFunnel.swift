//
//  VideoDuplicateFunnel.swift
//  PicSmart
//

import Photos
import AVFoundation
import CryptoKit
import Foundation

struct VideoDuplicateFunnel: Sendable {
    /// Runs the 3-stage exact duplicate video funnel:
    /// Stage 1: Dimensions + Rounded Duration (10th of a second) - eliminates 99% in < 2 ms
    /// Stage 2: Exact byte size (PHAssetResource)
    /// Stage 3: 15%, 50%, and 85% Keyframe sampling - neutralizes 0%/100% black frame trap without full GOP decoding
    static func scan(
        progressHandler: (@Sendable (AnalysisProgress) -> Void)? = nil
    ) async -> [AssetGroup] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let fetchResult = PHAsset.fetchAssets(with: .video, options: options)
        let total = fetchResult.count
        guard total > 1 else { return [] }
        
        // Stage 1: In-Memory Dimensions + Rounded Duration
        progressHandler?(AnalysisProgress(completed: 0, total: total, stage: "Checking video duration and dimensions…"))
        
        struct VideoMetaKey: Hashable {
            let width: Int
            let height: Int
            let durationTenths: Int
        }
        
        var metaBuckets = [VideoMetaKey: [PHAsset]]()
        var allVideos: [PHAsset] = []
        allVideos.reserveCapacity(total)
        
        fetchResult.enumerateObjects { asset, _, stop in
            if Task.isCancelled { stop.pointee = true; return }
            allVideos.append(asset)
            let tenths = Int((asset.duration * 10).rounded())
            let key = VideoMetaKey(width: asset.pixelWidth, height: asset.pixelHeight, durationTenths: tenths)
            metaBuckets[key, default: []].append(asset)
        }
        
        guard !Task.isCancelled else { return [] }
        
        let metaCandidates = metaBuckets.values.filter { $0.count > 1 }
        let totalCandidates = metaCandidates.reduce(0) { $0 + $1.count }
        guard totalCandidates > 1 else { return [] }
        
        // Stage 2: Exact Byte-Size Check
        progressHandler?(AnalysisProgress(completed: 0, total: totalCandidates, stage: "Comparing video storage sizes…"))
        
        var sizeBuckets = [Int64: [PHAsset]]()
        var assetFileSizes = [String: Int64]()
        var processed = 0
        
        for group in metaCandidates {
            for asset in group {
                if Task.isCancelled { return [] }
                let size = asset.primaryResourceFileSize ?? 0
                if size > 0 {
                    assetFileSizes[asset.localIdentifier] = size
                    sizeBuckets[size, default: []].append(asset)
                }
                processed += 1
                if processed % 10 == 0 || processed == totalCandidates {
                    progressHandler?(AnalysisProgress(completed: processed, total: totalCandidates, stage: "Comparing video storage sizes (\(processed)/\(totalCandidates))…"))
                }
            }
        }
        
        let sizeCandidates = sizeBuckets.values.filter { $0.count > 1 }
        guard !sizeCandidates.isEmpty else { return [] }
        
        // Stage 3: Keyframe Sampling at 15%, 50%, and 85%
        progressHandler?(AnalysisProgress(completed: 0, total: sizeCandidates.count, stage: "Verifying video keyframes…"))
        
        var finalGroups: [AssetGroup] = []
        
        for candidateList in sizeCandidates {
            if Task.isCancelled { break }
            
            var keyframeToAssets = [String: [PHAsset]]()
            for asset in candidateList {
                if let signature = await sampleVideoKeyframes(asset: asset) {
                    keyframeToAssets[signature, default: []].append(asset)
                }
            }
            
            for (sigKey, exactMatchList) in keyframeToAssets where exactMatchList.count > 1 {
                let sortedByOldest = exactMatchList.sorted {
                    ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast)
                }
                let keeper = sortedByOldest.first?.localIdentifier
                
                finalGroups.append(AssetGroup(
                    id: "dup_video_\(sigKey.prefix(12))",
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
    
    /// Samples keyframes at 15%, 50%, and 85% of duration using AVAssetImageGenerator snapped to nearest keyframe.
    private static func sampleVideoKeyframes(asset: PHAsset) async -> String? {
        await withCheckedContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.deliveryMode = .fastFormat
            options.isNetworkAccessAllowed = false
            
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                guard let urlAsset = avAsset else {
                    continuation.resume(returning: nil)
                    return
                }
                
                let generator = AVAssetImageGenerator(asset: urlAsset)
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: 64, height: 64)
                generator.requestedTimeToleranceBefore = CMTime(seconds: 1.0, preferredTimescale: 600)
                generator.requestedTimeToleranceAfter = CMTime(seconds: 1.0, preferredTimescale: 600)
                
                let totalSec = asset.duration
                let timestamps = [
                    CMTime(seconds: totalSec * 0.15, preferredTimescale: 600),
                    CMTime(seconds: totalSec * 0.50, preferredTimescale: 600),
                    CMTime(seconds: totalSec * 0.85, preferredTimescale: 600)
                ]
                
                var combinedBytes = [UInt8]()
                for time in timestamps {
                    autoreleasepool {
                        if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil),
                           let matrix = MatrixDownsampler.downsampleToGrayscale(image: cgImage, targetWidth: 16, targetHeight: 16) {
                            combinedBytes.append(contentsOf: matrix.pixels)
                        }
                    }
                }
                
                if combinedBytes.isEmpty {
                    continuation.resume(returning: nil)
                } else {
                    let hash = SHA256.hash(data: combinedBytes)
                    let hashString = hash.map { String(format: "%02x", $0) }.joined()
                    continuation.resume(returning: hashString)
                }
            }
        }
    }
}
