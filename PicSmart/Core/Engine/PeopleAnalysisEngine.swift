//
//  PeopleAnalysisEngine.swift
//  PicSmart
//

import Foundation
import Photos
@preconcurrency import Vision
import CoreGraphics
import QuartzCore

struct DetectedFacePrint: @unchecked Sendable {
    let asset: PHAsset
    let box: CGRect
    let featurePrint: VNFeaturePrintObservation
}

struct AssetFaceResult: @unchecked Sendable {
    let item: PersonPhotoItem?
    let faces: [DetectedFacePrint]
}

struct PersonCluster: Identifiable, Sendable {
    let id: String
    var name: String?
    var avatarAsset: PHAsset
    var avatarFaceBoundingBox: CGRect
    var assets: [PHAsset]
    
    var displayName: String {
        if let name, !name.trimmingCharacters(in: .whitespaces).isEmpty {
            return name
        }
        return "Person"
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
        
        var photoItems: [PersonPhotoItem] = []
        var detectedFaces: [DetectedFacePrint] = []
        
        var completedCount = 0
        var lastProgressTime = CACurrentMediaTime()
        progressHandler?(AnalysisProgress(
            completed: 0,
            total: totalCount,
            stage: "Detecting faces (0/\(totalCount))…"
        ))
        
        let workerCount = 3
        var nextIndex = 0
        
        await withTaskGroup(of: AssetFaceResult.self) { group in
            while nextIndex < min(workerCount, allAssets.count) {
                let asset = allAssets[nextIndex]
                nextIndex += 1
                group.addTask {
                    await self.extractFacesAndPrints(for: asset)
                }
            }
            
            while let result = await group.next() {
                if Task.isCancelled { break }
                completedCount += 1
                
                if let item = result.item, item.faceCount > 0 {
                    photoItems.append(item)
                    detectedFaces.append(contentsOf: result.faces)
                }
                
                let now = CACurrentMediaTime()
                if now - lastProgressTime >= 0.15 || completedCount == totalCount {
                    lastProgressTime = now
                    progressHandler?(AnalysisProgress(
                        completed: completedCount,
                        total: totalCount,
                        stage: "Detecting & clustering faces (\(completedCount)/\(totalCount))…"
                    ))
                }
                
                await AnalysisPipelineCoordinator.shared.yieldIfPreempted(for: .people)
                if !Task.isCancelled && nextIndex < allAssets.count {
                    let nextAsset = allAssets[nextIndex]
                    nextIndex += 1
                    group.addTask {
                        await self.extractFacesAndPrints(for: nextAsset)
                    }
                }
            }
        }
        
        // Identity Clustering with greedy nearest-neighbor centroid aggregation
        progressHandler?(AnalysisProgress(
            completed: totalCount,
            total: totalCount,
            stage: "Clustering individual identities…"
        ))
        
        struct RawCluster {
            let id: String
            let avatarAsset: PHAsset
            let avatarBox: CGRect
            let representativePrint: VNFeaturePrintObservation
            var memberAssets: [PHAsset]
        }
        var rawClusters = [RawCluster]()
        
        for face in detectedFaces {
            var bestDistance: Float = 1.0
            var bestIndex: Int? = nil
            
            for (idx, cluster) in rawClusters.enumerated() {
                var dist: Float = 1.0
                try? cluster.representativePrint.computeDistance(&dist, to: face.featurePrint)
                if dist < bestDistance {
                    bestDistance = dist
                    bestIndex = idx
                }
            }
            
            // Distance threshold for same human identity (~0.38)
            if bestDistance <= 0.38, let matchIdx = bestIndex {
                if !rawClusters[matchIdx].memberAssets.contains(where: { $0.localIdentifier == face.asset.localIdentifier }) {
                    rawClusters[matchIdx].memberAssets.append(face.asset)
                }
            } else {
                let clusterId = "person_\(rawClusters.count + 1)"
                rawClusters.append(RawCluster(
                    id: clusterId,
                    avatarAsset: face.asset,
                    avatarBox: face.box,
                    representativePrint: face.featurePrint,
                    memberAssets: [face.asset]
                ))
            }
        }
        
        // Sort clusters by number of photos descending
        rawClusters.sort { $0.memberAssets.count > $1.memberAssets.count }
        
        var finalClusters: [PersonCluster] = []
        for (i, c) in rawClusters.enumerated() {
            finalClusters.append(PersonCluster(
                id: c.id,
                name: "Person \(i + 1)",
                avatarAsset: c.avatarAsset,
                avatarFaceBoundingBox: c.avatarBox,
                assets: c.memberAssets
            ))
        }
        
        return PeopleScanOutput(personClusters: finalClusters, allPhotoItems: photoItems)
    }
    
    private func extractFacesAndPrints(for asset: PHAsset) async -> AssetFaceResult {
        guard let cgImage = await ThumbnailService.shared.requestFastAnalysisThumbnail(for: asset, targetSize: CGSize(width: 320, height: 320)) else {
            return AssetFaceResult(item: nil, faces: [])
        }
        
        return autoreleasepool {
            let faceRequest = VNDetectFaceRectanglesRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
            
            do {
                try handler.perform([faceRequest])
                let observations = faceRequest.results ?? []
                guard !observations.isEmpty else {
                    return AssetFaceResult(item: nil, faces: [])
                }
                
                // Detect Blinks
                var hasBlink = false
                let landmarksRequest = VNDetectFaceLandmarksRequest()
                try? handler.perform([landmarksRequest])
                let landmarkResults = landmarksRequest.results ?? []
                for face in landmarkResults {
                    if let left = face.landmarks?.leftEye, let right = face.landmarks?.rightEye {
                        if eyeOpenRatio(left) < 0.14 || eyeOpenRatio(right) < 0.14 {
                            hasBlink = true
                            break
                        }
                    }
                }
                
                let imgW = CGFloat(cgImage.width)
                let imgH = CGFloat(cgImage.height)
                var facePrints: [DetectedFacePrint] = []
                
                for obs in observations {
                    let box = obs.boundingBox
                    let x = box.origin.x * imgW
                    let y = (1.0 - box.origin.y - box.size.height) * imgH
                    let w = box.size.width * imgW
                    let h = box.size.height * imgH
                    
                    // Add 20% margin to include hair/ears for stable facial identity prints
                    let marginX = w * 0.20
                    let marginY = h * 0.20
                    let cropRect = CGRect(
                        x: max(0, x - marginX),
                        y: max(0, y - marginY),
                        width: min(imgW - max(0, x - marginX), w + 2 * marginX),
                        height: min(imgH - max(0, y - marginY), h + 2 * marginY)
                    )
                    
                    guard let faceChip = cgImage.cropping(to: cropRect) else { continue }
                    
                    let printRequest = VNGenerateImageFeaturePrintRequest()
                    printRequest.imageCropAndScaleOption = .scaleFill
                    let chipHandler = VNImageRequestHandler(cgImage: faceChip, orientation: .up, options: [:])
                    try? chipHandler.perform([printRequest])
                    
                    if let printObs = printRequest.results?.first as? VNFeaturePrintObservation {
                        facePrints.append(DetectedFacePrint(asset: asset, box: box, featurePrint: printObs))
                    }
                }
                
                let size = asset.primaryResourceFileSize ?? 3_500_000
                let item = PersonPhotoItem(
                    asset: asset,
                    faceCount: observations.count,
                    hasBlinkedEyes: hasBlink,
                    averageQuality: 1.0,
                    fileSize: size
                )
                
                return AssetFaceResult(item: item, faces: facePrints)
            } catch {
                return AssetFaceResult(item: nil, faces: [])
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
}
