//
//  PeopleAnalysisEngine.swift
//  PicSmart
//

import Foundation
import Photos
@preconcurrency import Vision
import CoreGraphics
import QuartzCore
import Accelerate

struct AssetFaceResult: @unchecked Sendable {
    let item: PersonPhotoItem?
    let faces: [BiometricFaceItem]
    let newEmbeddings: [FaceEmbeddingDTO]
}

struct IncrementalFaceMatchResult: Sendable {
    let matchedClusterId: String?
    let newCluster: PersonCluster?
    let asset: PHAsset
}

struct PersonCluster: Identifiable, Sendable {
    let id: String
    var name: String?
    var avatarAsset: PHAsset
    var avatarFaceBoundingBox: CGRect
    var assets: [PHAsset]
    var isFavorite: Bool = false
    var keyAssetId: String? = nil
    var representativeEmbedding: [Float]? = nil
    
    var displayName: String {
        if let name, !name.trimmingCharacters(in: .whitespaces).isEmpty {
            return name
        }
        return "Unnamed"
    }
    
    var isNamed: Bool {
        if let name, !name.trimmingCharacters(in: .whitespaces).isEmpty {
            return true
        }
        return false
    }
    
    var count: Int {
        assets.count
    }
}

struct PersonPhotoItem: Identifiable, Sendable {
    var id: String { asset.localIdentifier }
    let asset: PHAsset
    let faceCount: Int
    let hasBlinkedEyes: Bool
    let averageQuality: Float
    let fileSize: Int64
    
    var isSoloPortrait: Bool { faceCount == 1 }
    var isGroupPhoto: Bool { faceCount >= 2 }
}

struct PeopleScanOutput: Sendable {
    let personClusters: [PersonCluster]
    let allPhotoItems: [PersonPhotoItem]
}

actor PeopleAnalysisEngine {
    static let shared = PeopleAnalysisEngine()
    
    private init() {}
    
    func scan(progressHandler: (@Sendable (AnalysisProgress) -> Void)? = nil) async -> PeopleScanOutput {
        // Prewarm Neural Engine model in background
        FaceEmbeddingEngine.shared.prewarm()
        
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        
        let fetchResult = PHAsset.fetchAssets(with: options)
        let totalCount = fetchResult.count
        guard totalCount > 0 else {
            return PeopleScanOutput(personClusters: [], allPhotoItems: [])
        }
        
        var allAssets: [PHAsset] = []
        allAssets.reserveCapacity(totalCount)
        fetchResult.enumerateObjects { asset, _, _ in
            allAssets.append(asset)
        }
        
        // Load pre-existing cached face embeddings to skip redundant neural inference
        let cachedList = (try? await PersistentClusterStore.shared.loadAllFaceEmbeddings()) ?? []
        var cachedByAsset: [String: [FaceEmbeddingDTO]] = [:]
        for c in cachedList {
            cachedByAsset[c.assetIdentifier, default: []].append(c)
        }
        
        // Load existing persisted person metadata (names, favorites, key photos)
        let existingPersisted = (try? await PersistentClusterStore.shared.loadPersonDTOs()) ?? []
        var assetToName = [String: String]()
        var assetToFav = [String: Bool]()
        var assetToKey = [String: String]()
        for p in existingPersisted {
            if let n = p.name, !n.isEmpty {
                for aid in p.memberAssetIds { assetToName[aid] = n }
            }
            if p.isFavorite {
                for aid in p.memberAssetIds { assetToFav[aid] = true }
            }
            if let k = p.keyAssetId {
                for aid in p.memberAssetIds { assetToKey[aid] = k }
            }
        }
        
        var photoItems: [PersonPhotoItem] = []
        var allBiometricFaces: [BiometricFaceItem] = []
        var newEmbeddingsToPersist: [FaceEmbeddingDTO] = []
        
        // 1. Separate already-cached assets from missing assets
        var missingAssets: [PHAsset] = []
        for asset in allAssets {
            if let cached = cachedByAsset[asset.localIdentifier] {
                let validFaces = cached.filter { $0.faceIndex != -1 }
                if !validFaces.isEmpty {
                    let biometricFaces = validFaces.map { dto in
                        BiometricFaceItem(
                            id: dto.id,
                            asset: asset,
                            boundingBox: dto.boundingBox,
                            captureQuality: dto.captureQuality,
                            embedding: dto.embedding
                        )
                    }
                    let size = asset.primaryResourceFileSize ?? 3_500_000
                    let item = PersonPhotoItem(
                        asset: asset,
                        faceCount: validFaces.count,
                        hasBlinkedEyes: false,
                        averageQuality: 1.0,
                        fileSize: size
                    )
                    photoItems.append(item)
                    allBiometricFaces.append(contentsOf: biometricFaces)
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
            stage: "Detecting & analyzing faces (\(completedCount)/\(totalCount))…"
        ))
        
        let workerCount = 3
        var nextIndex = 0
        
        if !missingAssets.isEmpty {
            await withTaskGroup(of: AssetFaceResult.self) { group in
                while nextIndex < min(workerCount, missingAssets.count) {
                    let asset = missingAssets[nextIndex]
                    nextIndex += 1
                    group.addTask {
                        await self.analyzeAsset(asset: asset, cachedDTOs: nil)
                    }
                }
                
                while let result = await group.next() {
                    if Task.isCancelled {
                        group.cancelAll()
                        break
                    }
                    completedCount += 1
                    
                    if let item = result.item, item.faceCount > 0 {
                        photoItems.append(item)
                        allBiometricFaces.append(contentsOf: result.faces)
                    }
                    if !result.newEmbeddings.isEmpty {
                        newEmbeddingsToPersist.append(contentsOf: result.newEmbeddings)
                    }
                    
                    // Periodic Flush every 25 embeddings to guarantee in-flight persistence
                    if newEmbeddingsToPersist.count >= 25 {
                        let chunk = newEmbeddingsToPersist
                        newEmbeddingsToPersist.removeAll(keepingCapacity: true)
                        Task.detached(priority: .utility) {
                            try? await PersistentClusterStore.shared.saveFaceEmbeddings(chunk)
                        }
                    }
                    
                    let now = CACurrentMediaTime()
                    if now - lastProgressTime >= 0.15 || completedCount == totalCount {
                        lastProgressTime = now
                        progressHandler?(AnalysisProgress(
                            completed: completedCount,
                            total: totalCount,
                            stage: "Detecting & embedding faces (\(completedCount)/\(totalCount))…"
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
                            await self.analyzeAsset(asset: nextAsset, cachedDTOs: nil)
                        }
                    }
                }
            }
        }
        
        // Persist remaining embeddings (< 25) to SwiftData
        if !newEmbeddingsToPersist.isEmpty {
            let toSave = newEmbeddingsToPersist
            newEmbeddingsToPersist.removeAll()
            Task.detached(priority: .utility) {
                try? await PersistentClusterStore.shared.saveFaceEmbeddings(toSave)
            }
        }
        
        // If cancelled during face detection/embedding, DO NOT run clustering!
        // Return partial photoItems immediately so checkpoints are preserved without corrupting clusters.
        guard !Task.isCancelled else {
            return PeopleScanOutput(personClusters: [], allPhotoItems: photoItems)
        }
        
        // Identity Clustering with Accelerate Cosine DBSCAN
        progressHandler?(AnalysisProgress(
            completed: totalCount,
            total: totalCount,
            stage: "Clustering identities with biometric DBSCAN…"
        ))
        
        // Cluster using standard MobileFaceNet cosine distance radius (0.40) and minSamples (2)
        let dbscanOutput = DBSCANClusteringEngine.cluster(
            faces: allBiometricFaces,
            epsilon: 0.40,
            minSamples: 2
        )
        
        var finalClusters: [PersonCluster] = []
        var clusterIndex = 1
        
        // 1. Convert dense clusters to PersonCluster
        for identity in dbscanOutput.identities {
            let memberAssets = identity.uniqueAssets
            let memberAssetIds = memberAssets.map(\.localIdentifier)
            
            // Check if any photo in this cluster was previously named or favorited
            let matchedName = memberAssetIds.compactMap { assetToName[$0] }.first
            let matchedFav = memberAssetIds.contains(where: { assetToFav[$0] == true })
            let matchedKey = memberAssetIds.compactMap { assetToKey[$0] }.first
            
            // Resolve key avatar asset
            let keyAsset = memberAssets.first(where: { $0.localIdentifier == matchedKey }) ?? identity.avatarFace.asset
            
            finalClusters.append(PersonCluster(
                id: "person_\(clusterIndex)",
                name: matchedName,
                avatarAsset: keyAsset,
                avatarFaceBoundingBox: identity.avatarFace.boundingBox,
                assets: memberAssets,
                isFavorite: matchedFav,
                keyAssetId: matchedKey,
                representativeEmbedding: identity.centroid
            ))
            clusterIndex += 1
        }
        
        // 2. Apple Photos singleton policy:
        // Isolated singleton/noise faces are excluded from the primary shelf UNLESS explicitly named by user
        var unclusteredByAsset: [String: [BiometricFaceItem]] = [:]
        for face in dbscanOutput.unclusteredFaces {
            unclusteredByAsset[face.asset.localIdentifier, default: []].append(face)
        }
        
        for (assetId, faces) in unclusteredByAsset {
            if let customName = assetToName[assetId], let firstFace = faces.first {
                let isFav = assetToFav[assetId] ?? false
                finalClusters.append(PersonCluster(
                    id: "person_\(clusterIndex)",
                    name: customName,
                    avatarAsset: firstFace.asset,
                    avatarFaceBoundingBox: firstFace.boundingBox,
                    assets: [firstFace.asset],
                    isFavorite: isFav,
                    keyAssetId: assetId,
                    representativeEmbedding: firstFace.embedding
                ))
                clusterIndex += 1
            }
        }
        
        // Sort clusters: Favorites first, then by photo count descending
        finalClusters.sort {
            if $0.isFavorite != $1.isFavorite {
                return $0.isFavorite && !$1.isFavorite
            }
            return $0.assets.count > $1.assets.count
        }
        
        return PeopleScanOutput(personClusters: finalClusters, allPhotoItems: photoItems)
    }
    
    private func analyzeAsset(asset: PHAsset, cachedDTOs: [FaceEmbeddingDTO]?) async -> AssetFaceResult {
        guard !Task.isCancelled else {
            return AssetFaceResult(item: nil, faces: [], newEmbeddings: [])
        }
        // If already cached in SwiftData, reconstruct in microseconds without re-running Vision / CoreML
        if let cachedDTOs, !cachedDTOs.isEmpty {
            let validFaces = cachedDTOs.filter { $0.faceIndex != -1 }
            if validFaces.isEmpty {
                return AssetFaceResult(item: nil, faces: [], newEmbeddings: [])
            }
            let biometricFaces = validFaces.map { dto in
                BiometricFaceItem(
                    id: dto.id,
                    asset: asset,
                    boundingBox: dto.boundingBox,
                    captureQuality: dto.captureQuality,
                    embedding: dto.embedding
                )
            }
            let size = asset.primaryResourceFileSize ?? 3_500_000
            let item = PersonPhotoItem(
                asset: asset,
                faceCount: validFaces.count,
                hasBlinkedEyes: false,
                averageQuality: 1.0,
                fileSize: size
            )
            return AssetFaceResult(item: item, faces: biometricFaces, newEmbeddings: [])
        }
        
        return await extractFacesAndBiometrics(for: asset)
    }
    
    private func extractFacesAndBiometrics(for asset: PHAsset) async -> AssetFaceResult {
        guard let cgImage = await ThumbnailService.shared.requestAnalysisThumbnail(
            for: asset,
            targetSize: CGSize(width: 1024, height: 1024)
        ) else {
            return AssetFaceResult(item: nil, faces: [], newEmbeddings: [])
        }
        
        return autoreleasepool {
            let landmarksRequest = VNDetectFaceLandmarksRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
            
            do {
                try handler.perform([landmarksRequest])
                let observations = landmarksRequest.results ?? []
                guard !observations.isEmpty else {
                    let noFaceDTO = FaceEmbeddingDTO(
                        id: "\(asset.localIdentifier)_-1",
                        assetIdentifier: asset.localIdentifier,
                        faceIndex: -1,
                        boundingBox: .zero,
                        captureQuality: 0,
                        embedding: []
                    )
                    return AssetFaceResult(item: nil, faces: [], newEmbeddings: [noFaceDTO])
                }
                
                let imgW = CGFloat(cgImage.width)
                let imgH = CGFloat(cgImage.height)
                
                var hasBlink = false
                var biometricFaces: [BiometricFaceItem] = []
                var newDTOs: [FaceEmbeddingDTO] = []
                
                for (faceIndex, face) in observations.enumerated() {
                    // Blink Detection — dual eye threshold
                    if let quality = face.faceCaptureQuality, quality >= 0.35 {
                        let faceAreaFraction = face.boundingBox.width * face.boundingBox.height
                        if faceAreaFraction >= 0.08,
                           let left = face.landmarks?.leftEye,
                           let right = face.landmarks?.rightEye {
                            let leftRatio = eyeOpenRatio(left)
                            let rightRatio = eyeOpenRatio(right)
                            if leftRatio < 0.12 && rightRatio < 0.12 {
                                hasBlink = true
                            }
                        }
                    }
                    
                    // Quality and pose gating for invariant biometric identification
                    guard FaceAlignmentEngine.shared.passesQualityGates(
                        observation: face,
                        imageWidth: imgW,
                        imageHeight: imgH,
                        minDimension: 64.0,
                        minQuality: 0.35,
                        maxYawAngle: 0.785398 // 45 degrees
                    ) else {
                        continue
                    }
                    
                    // Canonical affine landmark alignment to 112x112 chip
                    guard let alignedChip = FaceAlignmentEngine.shared.alignFace(from: cgImage, observation: face) else {
                        continue
                    }
                    
                    // MobileFaceNet CoreML feature extraction
                    guard let embedding = FaceEmbeddingEngine.shared.generateEmbedding(from: alignedChip) else {
                        continue
                    }
                    
                    let faceId = "\(asset.localIdentifier)_\(faceIndex)"
                    let quality = face.faceCaptureQuality ?? 0.5
                    
                    biometricFaces.append(BiometricFaceItem(
                        id: faceId,
                        asset: asset,
                        boundingBox: face.boundingBox,
                        captureQuality: quality,
                        embedding: embedding
                    ))
                    
                    newDTOs.append(FaceEmbeddingDTO(
                        id: faceId,
                        assetIdentifier: asset.localIdentifier,
                        faceIndex: faceIndex,
                        boundingBox: face.boundingBox,
                        captureQuality: quality,
                        embedding: embedding
                    ))
                }
                
                if newDTOs.isEmpty {
                    newDTOs.append(FaceEmbeddingDTO(
                        id: "\(asset.localIdentifier)_noface",
                        assetIdentifier: asset.localIdentifier,
                        faceIndex: -1,
                        boundingBox: .zero,
                        captureQuality: 0.0,
                        embedding: []
                    ))
                }
                
                let size = asset.primaryResourceFileSize ?? 3_500_000
                let item = PersonPhotoItem(
                    asset: asset,
                    faceCount: observations.count,
                    hasBlinkedEyes: hasBlink,
                    averageQuality: 1.0,
                    fileSize: size
                )
                
                return AssetFaceResult(item: item, faces: biometricFaces, newEmbeddings: newDTOs)
            } catch {
                return AssetFaceResult(item: nil, faces: [], newEmbeddings: [])
            }
        }
    }
    
    private nonisolated func eyeOpenRatio(_ eyeRegion: VNFaceLandmarkRegion2D) -> Double {
        let points = eyeRegion.normalizedPoints
        guard points.count >= 4 else { return 0.25 }
        let minY = points.map(\.y).min() ?? 0
        let maxY = points.map(\.y).max() ?? 0
        let minX = points.map(\.x).min() ?? 0
        let maxX = points.map(\.x).max() ?? 0
        let height = maxY - minY
        let width = maxX - minX
        guard width > 0 else { return 0.25 }
        return Double(height / width)
    }
    
    // MARK: - Incremental Face Clustering
    
    /// Incrementally analyzes a newly added photo.
    /// If a face matches an existing cluster's centroid (cosine distance <= 0.40), it updates the existing cluster.
    /// Otherwise, if a distinct face is detected, it creates a new person cluster.
    func processNewAssetIncrementally(
        _ asset: PHAsset,
        existingClusters: [PersistedPersonDTO]
    ) async -> IncrementalFaceMatchResult? {
        guard asset.mediaType == .image else { return nil }
        
        let faceResult = await extractFacesAndBiometrics(for: asset)
        guard let item = faceResult.item, item.faceCount > 0, !faceResult.faces.isEmpty else {
            return nil
        }
        
        // Save new embeddings to disk cache
        if !faceResult.newEmbeddings.isEmpty {
            let embeddingsToSave = faceResult.newEmbeddings
            Task.detached(priority: .utility) {
                try? await PersistentClusterStore.shared.saveFaceEmbeddings(embeddingsToSave)
            }
        }
        
        // Match the most prominent face in the photo
        guard let primaryFace = faceResult.faces.max(by: { $0.captureQuality < $1.captureQuality }) else {
            return nil
        }
        
        var bestMatchClusterId: String? = nil
        var minDistance: Float = Float.greatestFiniteMagnitude
        let threshold: Float = 0.40 // Standard MobileFaceNet cosine distance radius
        
        for cluster in existingClusters {
            guard let clusterEmbedding = cluster.representativeEmbedding,
                  clusterEmbedding.count == primaryFace.embedding.count else {
                continue
            }
            
            // Cosine distance = 1.0 - dotProduct (both are L2-normalized)
            var dot: Float = 0.0
            vDSP_dotpr(primaryFace.embedding, 1, clusterEmbedding, 1, &dot, vDSP_Length(primaryFace.embedding.count))
            let distance = 1.0 - dot
            
            if distance < minDistance {
                minDistance = distance
                if distance <= threshold {
                    bestMatchClusterId = cluster.id
                }
            }
        }
        
        if let matchedId = bestMatchClusterId {
            // Found existing cluster match!
            Task.detached(priority: .utility) {
                try? await PersistentClusterStore.shared.addAssetToPersonCluster(
                    clusterId: matchedId,
                    assetIdentifier: asset.localIdentifier
                )
            }
            return IncrementalFaceMatchResult(
                matchedClusterId: matchedId,
                newCluster: nil,
                asset: asset
            )
        } else {
            // New distinct person cluster
            let newId = "person_\(UUID().uuidString.prefix(8))"
            let newCluster = PersonCluster(
                id: newId,
                name: nil,
                avatarAsset: asset,
                avatarFaceBoundingBox: primaryFace.boundingBox,
                assets: [asset],
                isFavorite: false,
                keyAssetId: asset.localIdentifier,
                representativeEmbedding: primaryFace.embedding
            )
            
            let dto = PersistedPersonDTO(
                id: newId,
                name: nil,
                avatarAssetId: asset.localIdentifier,
                avatarFaceBoundingBox: primaryFace.boundingBox,
                memberAssetIds: [asset.localIdentifier],
                isFavorite: false,
                keyAssetId: asset.localIdentifier,
                representativeEmbedding: primaryFace.embedding
            )
            
            Task.detached(priority: .utility) {
                try? await PersistentClusterStore.shared.insertNewPersonCluster(dto: dto)
            }
            
            return IncrementalFaceMatchResult(
                matchedClusterId: nil,
                newCluster: newCluster,
                asset: asset
            )
        }
    }
}
