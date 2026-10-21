//
//  MediaAnalyzerEngine.swift
//  PicSmart
//

import Photos
import Foundation

/// Central background actor coordinating multi-stage filtering funnels and streaming progressive results.
actor MediaAnalyzerEngine {
    static let shared = MediaAnalyzerEngine()
    
    // In-memory size cache so subsequent opens are instantaneous
    private var videoSizeCache = [String: Int64]()
    
    // In-flight tasks to preserve background continuity across navigation transitions
    private var runningDuplicatePhotosTask: Task<[AssetGroup], Never>?
    private var runningDuplicateVideosTask: Task<[AssetGroup], Never>?
    private var runningSimilarPhotosTask: Task<[AssetGroup], Never>?
    
    // MARK: - Large Videos Progressive Stream
    
    /// Streams large videos progressively as sizes are calculated off the main thread.
    /// Emits updated sorted snapshots every batchSize items so the user sees results immediately.
    func streamLargeVideos(
        minThresholdBytes: Int64,
        batchYieldInterval: Int = 25
    ) -> AsyncStream<(assets: [PHAsset], fileSizes: [String: Int64], progress: AnalysisProgress)> {
        AsyncStream { continuation in
            Task.detached(priority: .userInitiated) {
                let options = PHFetchOptions()
                options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
                let fetchResult = PHAsset.fetchAssets(with: .video, options: options)
                let total = fetchResult.count
                
                guard total > 0 else {
                    continuation.yield(([], [:], AnalysisProgress(completed: 0, total: 0, stage: "Complete")))
                    continuation.finish()
                    return
                }
                
                var items: [(asset: PHAsset, size: Int64)] = []
                var sizeMap: [String: Int64] = [:]
                var processed = 0
                
                fetchResult.enumerateObjects { asset, _, stop in
                    if Task.isCancelled {
                        stop.pointee = true
                        return
                    }
                    
                    let size = asset.primaryResourceFileSize ?? 0
                    if size >= minThresholdBytes {
                        items.append((asset, size))
                        sizeMap[asset.localIdentifier] = size
                    }
                    processed += 1
                    
                    // Yield progressive update every batchYieldInterval items
                    if processed % batchYieldInterval == 0 || processed == total {
                        let sortedSnapshot = items.sorted { $0.size > $1.size }.map(\.asset)
                        let progress = AnalysisProgress(
                            completed: processed,
                            total: total,
                            stage: "Scanning videos (\(processed)/\(total))…"
                        )
                        continuation.yield((sortedSnapshot, sizeMap, progress))
                    }
                }
                
                let finalSorted = items.sorted { $0.size > $1.size }.map(\.asset)
                continuation.yield((finalSorted, sizeMap, AnalysisProgress(completed: total, total: total, stage: "Complete")))
                continuation.finish()
            }
        }
    }
    
    // MARK: - Category Scanners
    
    func scanDuplicatePhotos(
        progressHandler: (@Sendable (AnalysisProgress) -> Void)? = nil
    ) async -> [AssetGroup] {
        await ExactDuplicateFunnel.scan(progressHandler: progressHandler)
    }
    
    func scanDuplicateVideos(
        progressHandler: (@Sendable (AnalysisProgress) -> Void)? = nil
    ) async -> [AssetGroup] {
        await VideoDuplicateFunnel.scan(progressHandler: progressHandler)
    }
    
    func scanSimilarPhotos(
        progressHandler: (@Sendable (AnalysisProgress) -> Void)? = nil
    ) async -> [AssetGroup] {
        await SimilarPhotosFunnel.scan(progressHandler: progressHandler)
    }
    
    // MARK: - Quick Large Video Count
    
    func countLargeVideos(minThresholdBytes: Int64) async -> Int {
        await Task.detached(priority: .utility) {
            let options = PHFetchOptions()
            let fetchResult = PHAsset.fetchAssets(with: .video, options: options)
            guard fetchResult.count > 0 else { return 0 }
            
            var count = 0
            fetchResult.enumerateObjects { asset, _, stop in
                if Task.isCancelled { stop.pointee = true; return }
                let size = asset.primaryResourceFileSize ?? 0
                if size >= minThresholdBytes {
                    count += 1
                }
            }
            return count
        }.value
    }
}
