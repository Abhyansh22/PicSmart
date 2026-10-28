//
//  SimilarPhotosFunnel.swift
//  PicSmart
//

import Photos
import Vision
import Foundation
import QuartzCore

struct SimilarPhotosFunnel: Sendable {
    private struct CandidateSignature: Hashable, Sendable {
        let id: String
        let asset: PHAsset
        let gradientHash: UInt64
        let averageLuminance: UInt8
        let aspectBand: Int
        let weekBucket: Int64
        let sharpnessScore: Double
        let observation: VNFeaturePrintObservation?
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
        
        static func == (lhs: CandidateSignature, rhs: CandidateSignature) -> Bool {
            lhs.id == rhs.id
        }
    }
    
    private struct FingerprintResult: Sendable {
        let signature: CandidateSignature?
        let dto: VisualSignatureDTO?
    }
    
    /// Runs the hybrid Matrix-to-Vision similar photo funnel:
    /// Stage 1: 64-bit dHash + Luma + Laplacian sharpness (cached in SwiftData)
    /// Stage 2: Bitwise clustering into the Intermediate Batch (Hamming <= 12, Luma <= 35)
    /// Stage 3: Neural Vision verification on Intermediate Batch only (0.005 < dist <= 0.45)
    /// Stage 4: Complete-Linkage clustering (no similarity chaining) & Best-Shot tagging
    static func scan(
        progressHandler: (@Sendable (AnalysisProgress) -> Void)? = nil
    ) async -> [AssetGroup] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let fetchResult = PHAsset.fetchAssets(with: .image, options: options)
        let total = fetchResult.count
        guard total > 1 else { return [] }
        
        // Filter out screenshots
        var eligibleAssets: [PHAsset] = []
        var assetMap = [String: PHAsset]()
        
        fetchResult.enumerateObjects { asset, _, stop in
            if Task.isCancelled { stop.pointee = true; return }
            if !asset.mediaSubtypes.contains(.photoScreenshot) {
                eligibleAssets.append(asset)
                assetMap[asset.localIdentifier] = asset
            }
        }
        
        guard !Task.isCancelled, eligibleAssets.count > 1 else { return [] }
        
        // Stage 1: Check and generate visual signatures (cached in SwiftData)
        progressHandler?(AnalysisProgress(completed: 0, total: eligibleAssets.count, stage: "Checking visual signatures…"))
        
        let cachedStore = await FeatureVectorStore.shared.loadAllSignatures()
        var signatures: [CandidateSignature] = []
        signatures.reserveCapacity(eligibleAssets.count)
        
        var missingAssets: [PHAsset] = []
        for asset in eligibleAssets {
            if let cached = cachedStore[asset.localIdentifier] {
                signatures.append(CandidateSignature(
                    id: asset.localIdentifier,
                    asset: asset,
                    gradientHash: cached.gradientHash,
                    averageLuminance: cached.averageLuminance,
                    aspectBand: cached.aspectBand,
                    weekBucket: cached.creationWeekBucket,
                    sharpnessScore: cached.sharpnessScore,
                    observation: cached.observation
                ))
            } else {
                missingAssets.append(asset)
            }
        }
        
        var toSave: [VisualSignatureDTO] = []
        let totalCount = eligibleAssets.count
        var completedCount = signatures.count
        var lastProgressTime = CACurrentMediaTime()
        
        // Initial progress event
        progressHandler?(AnalysisProgress(
            completed: completedCount,
            total: totalCount,
            stage: "Fingerprinting photos (\(completedCount)/\(totalCount))…"
        ))
        
        if !missingAssets.isEmpty {
            let workerCount = 3
            var nextMissingIndex = 0
            
            await withTaskGroup(of: FingerprintResult.self) { group in
                // 1. Prime the queue with at most 3 concurrent requests (producer-consumer cap)
                while nextMissingIndex < min(workerCount, missingAssets.count) {
                    let asset = missingAssets[nextMissingIndex]
                    nextMissingIndex += 1
                    group.addTask {
                        await computeFingerprint(for: asset)
                    }
                }
                
                // 2. Sliding window: as one finishes, collect and enqueue the next
                while let result = await group.next() {
                    if Task.isCancelled {
                        group.cancelAll()
                        break
                    }
                    
                    if let sig = result.signature, let dto = result.dto {
                        signatures.append(sig)
                        toSave.append(dto)
                    }
                    completedCount += 1
                    
                    // Periodic Flush every 25 completed items to guarantee in-flight persistence
                    if toSave.count >= 25 {
                        let chunk = toSave
                        toSave.removeAll(keepingCapacity: true)
                        await FeatureVectorStore.shared.saveSignatures(chunk)
                    }
                    
                    // Area 4: Time-throttled progress updates (every 150ms or on completion)
                    let now = CACurrentMediaTime()
                    if now - lastProgressTime >= 0.15 || completedCount == totalCount {
                        lastProgressTime = now
                        progressHandler?(AnalysisProgress(
                            completed: completedCount,
                            total: totalCount,
                            stage: "Fingerprinting photos (\(completedCount)/\(totalCount))…"
                        ))
                    }
                    
                    // Sliding window enqueue
                    if Task.isCancelled {
                        group.cancelAll()
                        break
                    }
                    if nextMissingIndex < missingAssets.count {
                        let nextAsset = missingAssets[nextMissingIndex]
                        nextMissingIndex += 1
                        group.addTask {
                            await computeFingerprint(for: nextAsset)
                        }
                    }
                }
            }
        }
        
        // Flush remaining signatures (< 25) upon loop completion
        if !toSave.isEmpty {
            await FeatureVectorStore.shared.saveSignatures(toSave)
            toSave.removeAll()
        }
        
        guard !Task.isCancelled else { return [] }
        
        // Stage 2: Bitwise Matrix Sieve into the Intermediate Batch
        progressHandler?(AnalysisProgress(completed: 0, total: signatures.count, stage: "Sifting candidate clusters…"))
        
        struct SieveBucketKey: Hashable {
            let aspectBand: Int
            let weekBucket: Int64
        }
        
        var sieveBuckets = [SieveBucketKey: [CandidateSignature]]()
        for sig in signatures {
            let key = SieveBucketKey(aspectBand: sig.aspectBand, weekBucket: sig.weekBucket)
            sieveBuckets[key, default: []].append(sig)
        }
        
        // Filter candidate pairs with Hamming distance <= 12 and Delta Luma <= 35
        var candidatePairs: [(CandidateSignature, CandidateSignature)] = []
        for (_, bucketItems) in sieveBuckets where bucketItems.count > 1 {
            for i in 0..<(bucketItems.count - 1) {
                for j in (i + 1)..<bucketItems.count {
                    let a = bucketItems[i]
                    let b = bucketItems[j]
                    let hamming = DifferenceHash.hammingDistance(a.gradientHash, b.gradientHash)
                    let deltaLuma = abs(Int(a.averageLuminance) - Int(b.averageLuminance))
                    
                    if hamming <= 12 && deltaLuma <= 35 {
                        candidatePairs.append((a, b))
                    }
                }
            }
        }
        
        guard !candidatePairs.isEmpty else { return [] }
        
        // Stage 3: Neural Vision Verification on the Intermediate Batch Only
        progressHandler?(AnalysisProgress(completed: 0, total: candidatePairs.count, stage: "Verifying with Vision neural engine…"))
        
        // Gather all unique assets that need Vision feature prints
        var neededPrintIds = Set<String>()
        for pair in candidatePairs {
            if pair.0.observation == nil { neededPrintIds.insert(pair.0.id) }
            if pair.1.observation == nil { neededPrintIds.insert(pair.1.id) }
        }
        
        var observations = [String: VNFeaturePrintObservation]()
        // Populate existing observations
        for sig in signatures {
            if let obs = sig.observation {
                observations[sig.id] = obs
            }
        }
        
        // Generate Vision prints only for the surviving candidates
        var printDone = 0
        var lastPrintProgressTime = CACurrentMediaTime()
        for id in neededPrintIds {
            if Task.isCancelled { return [] }
            if let asset = assetMap[id] {
                if let obs = await generateVisionFeaturePrint(for: asset) {
                    observations[id] = obs
                    if let data = try? NSKeyedArchiver.archivedData(withRootObject: obs, requiringSecureCoding: true) {
                        Task {
                            await FeatureVectorStore.shared.updateFeatureData(for: id, data: data)
                        }
                    }
                }
            }
            printDone += 1
            let now = CACurrentMediaTime()
            if now - lastPrintProgressTime >= 0.15 || printDone == neededPrintIds.count {
                lastPrintProgressTime = now
                progressHandler?(AnalysisProgress(completed: printDone, total: neededPrintIds.count, stage: "Neural verification (\(printDone)/\(neededPrintIds.count))…"))
            }
        }
        
        // Evaluate Vision distances (0.005 < dist <= 0.45)
        var confirmedSimilarPairs = [(CandidateSignature, CandidateSignature)]()
        for (a, b) in candidatePairs {
            guard let printA = observations[a.id], let printB = observations[b.id] else { continue }
            var distance: Float = 1.0
            try? printA.computeDistance(&distance, to: printB)
            
            // If distance <= 0.005 it's an exact duplicate; only 0.005 < dist <= 0.45 is similar
            if distance > 0.005 && distance <= 0.45 {
                confirmedSimilarPairs.append((a, b))
            }
        }
        
        // Stage 4: Complete-Linkage Clustering to Prevent Chaining Creep
        let uniqueParticipants = Array(Set(confirmedSimilarPairs.flatMap { [$0.0, $0.1] }))
        let similarPairLookup = Set(confirmedSimilarPairs.map { "\($0.0.id)_\($0.1.id)" } + confirmedSimilarPairs.map { "\($0.1.id)_\($0.0.id)" })
        
        let clusters: [[CandidateSignature]] = CompleteLinkClustering.cluster(items: uniqueParticipants) { (left: CandidateSignature, right: CandidateSignature) in
            similarPairLookup.contains("\(left.id)_\(right.id)")
        }
        
        // Deferred byte size lookup: query ONLY the few assets in confirmed clusters
        var assetFileSizes = [String: Int64]()
        for cluster in clusters {
            for candidate in cluster {
                autoreleasepool {
                    if let size = candidate.asset.primaryResourceFileSize {
                        assetFileSizes[candidate.id] = size
                    }
                }
            }
        }
        
        // Build final AssetGroups and tag "Best Shot" using Laplacian sharpness score
        var finalGroups: [AssetGroup] = []
        for (index, cluster) in clusters.enumerated() {
            let sortedAssets = cluster.map(\.asset)
            
            // Best Shot is the member with highest sharpness score
            let bestCandidate = cluster.max(by: { $0.sharpnessScore < $1.sharpnessScore })
            let bestShotId = bestCandidate?.id ?? cluster.first?.id
            
            finalGroups.append(AssetGroup(
                id: "similar_group_\(index + 1)",
                assets: sortedAssets,
                keeperId: bestShotId, // Best shot is kept by default
                bestShotId: bestShotId,
                fileSizes: assetFileSizes,
                similarityScore: 0.85
            ))
        }
        
        return finalGroups
    }
    
    private static func computeFingerprint(for asset: PHAsset) async -> FingerprintResult {
        guard !Task.isCancelled else {
            return FingerprintResult(signature: nil, dto: nil)
        }
        guard let cgImage = await ThumbnailService.shared.requestFastAnalysisThumbnail(for: asset, targetSize: CGSize(width: 32, height: 32)) else {
            return FingerprintResult(signature: nil, dto: nil)
        }
        
        return autoreleasepool {
            guard let hashData = DifferenceHash.compute(from: cgImage) else {
                return FingerprintResult(signature: nil, dto: nil)
            }
            let sharpness = LaplacianKernel.computeSharpnessVariance(from: cgImage)
            
            let sig = CandidateSignature(
                id: asset.localIdentifier,
                asset: asset,
                gradientHash: hashData.hash,
                averageLuminance: hashData.luma,
                aspectBand: asset.aspectRatioBand,
                weekBucket: asset.creationWeekBucket,
                sharpnessScore: sharpness,
                observation: nil
            )
            
            let dto = VisualSignatureDTO(
                localIdentifier: asset.localIdentifier,
                gradientHash: hashData.hash,
                averageLuminance: hashData.luma,
                aspectBand: asset.aspectRatioBand,
                creationWeekBucket: asset.creationWeekBucket,
                sharpnessScore: sharpness,
                featureData: nil
            )
            
            return FingerprintResult(signature: sig, dto: dto)
        }
    }
    
    private static func generateVisionFeaturePrint(for asset: PHAsset) async -> VNFeaturePrintObservation? {
        guard let cgImage = await ThumbnailService.shared.requestFastAnalysisThumbnail(for: asset, targetSize: CGSize(width: 256, height: 256)) else {
            return nil
        }
        return autoreleasepool {
            let request = VNGenerateImageFeaturePrintRequest()
            request.imageCropAndScaleOption = .scaleFit
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
            return request.results?.first as? VNFeaturePrintObservation
        }
    }
}
