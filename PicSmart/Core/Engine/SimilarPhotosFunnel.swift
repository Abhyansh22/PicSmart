//
//  SimilarPhotosFunnel.swift
//  PicSmart
//

import Photos
import Vision
import Foundation

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
        
        var toSave: [VisualSignatureDTO] = []
        var completed = 0
        
        for asset in eligibleAssets {
            if Task.isCancelled { return [] }
            
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
                autoreleasepool {
                    if let cgImage = ThumbnailService.shared.requestFastAnalysisThumbnail(for: asset, targetSize: CGSize(width: 32, height: 32)),
                       let hashData = DifferenceHash.compute(from: cgImage) {
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
                        signatures.append(sig)
                        
                        toSave.append(VisualSignatureDTO(
                            localIdentifier: asset.localIdentifier,
                            gradientHash: hashData.hash,
                            averageLuminance: hashData.luma,
                            aspectBand: asset.aspectRatioBand,
                            creationWeekBucket: asset.creationWeekBucket,
                            sharpnessScore: sharpness,
                            featureData: nil
                        ))
                    }
                }
            }
            
            completed += 1
            if completed % 25 == 0 || completed == eligibleAssets.count {
                await Task.yield()
                progressHandler?(AnalysisProgress(completed: completed, total: eligibleAssets.count, stage: "Fingerprinting photos (\(completed)/\(eligibleAssets.count))…"))
            }
        }
        
        if !toSave.isEmpty {
            await FeatureVectorStore.shared.saveSignatures(toSave)
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
        for id in neededPrintIds {
            if Task.isCancelled { return [] }
            if let asset = assetMap[id] {
                autoreleasepool {
                    if let obs = generateVisionFeaturePrint(for: asset) {
                        observations[id] = obs
                        if let data = try? NSKeyedArchiver.archivedData(withRootObject: obs, requiringSecureCoding: true) {
                            Task {
                                await FeatureVectorStore.shared.updateFeatureData(for: id, data: data)
                            }
                        }
                    }
                }
            }
            printDone += 1
            if printDone % 10 == 0 || printDone == neededPrintIds.count {
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
    
    private static func generateVisionFeaturePrint(for asset: PHAsset) -> VNFeaturePrintObservation? {
        guard let cgImage = ThumbnailService.shared.requestFastAnalysisThumbnail(for: asset, targetSize: CGSize(width: 256, height: 256)) else {
            return nil
        }
        let request = VNGenerateImageFeaturePrintRequest()
        request.imageCropAndScaleOption = .scaleFit
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
        return request.results?.first as? VNFeaturePrintObservation
    }
}
