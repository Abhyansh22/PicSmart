//
//  PeopleAnalysisEngine.swift
//  PicSmart
//

import Foundation
import Photos
import Vision
import CoreGraphics
import QuartzCore

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

actor PeopleAnalysisEngine {
    static let shared = PeopleAnalysisEngine()
    
    private var memoryCache: [String: PersonPhotoItem] = [:]
    
    private init() {}
    
    func scan(progressHandler: (@Sendable (AnalysisProgress) -> Void)? = nil) async -> [PersonPhotoItem] {
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
        
        var results: [PersonPhotoItem] = []
        var missingAssets: [PHAsset] = []
        
        for asset in allAssets {
            if let cached = memoryCache[asset.localIdentifier] {
                if cached.faceCount > 0 {
                    results.append(cached)
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
            stage: "Detecting faces (\(completedCount)/\(totalCount))…"
        ))
        
        if !missingAssets.isEmpty {
            let workerCount = 3
            var nextIndex = 0
            
            await withTaskGroup(of: PersonPhotoItem?.self) { group in
                while nextIndex < min(workerCount, missingAssets.count) {
                    let asset = missingAssets[nextIndex]
                    nextIndex += 1
                    group.addTask {
                        await self.analyzeAssetForFaces(asset)
                    }
                }
                
                while let item = await group.next() {
                    if Task.isCancelled { break }
                    completedCount += 1
                    
                    if let item {
                        self.memoryCache[item.id] = item
                        if item.faceCount > 0 {
                            results.append(item)
                        }
                    }
                    
                    let now = CACurrentMediaTime()
                    if now - lastProgressTime >= 0.15 || completedCount == totalCount {
                        lastProgressTime = now
                        progressHandler?(AnalysisProgress(
                            completed: completedCount,
                            total: totalCount,
                            stage: "Detecting faces (\(completedCount)/\(totalCount))…"
                        ))
                    }
                    
                    await AnalysisPipelineCoordinator.shared.yieldIfPreempted(for: .people)
                    if !Task.isCancelled && nextIndex < missingAssets.count {
                        let nextAsset = missingAssets[nextIndex]
                        nextIndex += 1
                        group.addTask {
                            await self.analyzeAssetForFaces(nextAsset)
                        }
                    }
                }
            }
        }
        
        return results
    }
    
    private func analyzeAssetForFaces(_ asset: PHAsset) async -> PersonPhotoItem? {
        // Request medium-res thumbnail for high-precision face & eye landmark detection
        guard let cgImage = await ThumbnailService.shared.requestFastAnalysisThumbnail(for: asset, targetSize: CGSize(width: 320, height: 320)) else {
            return nil
        }
        
        return autoreleasepool {
            let request = VNDetectFaceRectanglesRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
            
            do {
                try handler.perform([request])
                let faceObservations = request.results as? [VNFaceObservation] ?? []
                guard !faceObservations.isEmpty else {
                    return PersonPhotoItem(
                        asset: asset,
                        faceCount: 0,
                        hasBlinkedEyes: false,
                        averageQuality: 0,
                        fileSize: asset.primaryResourceFileSize ?? 3_500_000
                    )
                }
                
                // If faces are found, run landmarks to detect blinking / closed eyes
                var hasBlink = false
                let landmarksRequest = VNDetectFaceLandmarksRequest()
                try? handler.perform([landmarksRequest])
                let landmarkResults = landmarksRequest.results as? [VNFaceObservation] ?? []
                
                for face in landmarkResults {
                    if let leftEye = face.landmarks?.leftEye, let rightEye = face.landmarks?.rightEye {
                        let leftRatio = eyeOpenRatio(leftEye)
                        let rightRatio = eyeOpenRatio(rightEye)
                        // If both eyes appear squished/closed while face is frontal
                        if leftRatio < 0.14 || rightRatio < 0.14 {
                            hasBlink = true
                            break
                        }
                    }
                }
                
                let size = asset.primaryResourceFileSize ?? 3_500_000
                return PersonPhotoItem(
                    asset: asset,
                    faceCount: faceObservations.count,
                    hasBlinkedEyes: hasBlink,
                    averageQuality: 1.0,
                    fileSize: size
                )
            } catch {
                return nil
            }
        }
    }
    
    /// Computes eye aspect ratio (height / width). Closed eyes produce an aspect ratio < 0.14
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
