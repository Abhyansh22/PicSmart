//
//  CachedFaceEmbedding.swift
//  PicSmart
//

import Foundation
import SwiftData
import CoreGraphics

/// SwiftData entity caching extracted facial embeddings for PHAssets.
/// Avoids re-running Vision detection and CoreML neural inference on cold app launches.
@Model
final class CachedFaceEmbedding {
    @Attribute(.unique) var id: String // "\(assetIdentifier)_\(faceIndex)"
    var assetIdentifier: String
    var faceIndex: Int
    var boundingBoxX: Double
    var boundingBoxY: Double
    var boundingBoxWidth: Double
    var boundingBoxHeight: Double
    var captureQuality: Float
    @Attribute(.externalStorage) var embeddingData: Data
    var embeddingDimension: Int
    var createdAt: Date
    
    init(
        id: String,
        assetIdentifier: String,
        faceIndex: Int,
        boundingBox: CGRect,
        captureQuality: Float,
        embedding: [Float]
    ) {
        self.id = id
        self.assetIdentifier = assetIdentifier
        self.faceIndex = faceIndex
        self.boundingBoxX = Double(boundingBox.origin.x)
        self.boundingBoxY = Double(boundingBox.origin.y)
        self.boundingBoxWidth = Double(boundingBox.size.width)
        self.boundingBoxHeight = Double(boundingBox.size.height)
        self.captureQuality = captureQuality
        self.embeddingDimension = embedding.count
        
        let data = embedding.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
        self.embeddingData = data
        self.createdAt = Date()
    }
    
    var boundingBox: CGRect {
        CGRect(x: boundingBoxX, y: boundingBoxY, width: boundingBoxWidth, height: boundingBoxHeight)
    }
    
    var embedding: [Float] {
        guard embeddingData.count >= embeddingDimension * MemoryLayout<Float>.size else { return [] }
        return embeddingData.withUnsafeBytes { rawBuffer in
            Array(rawBuffer.bindMemory(to: Float.self).prefix(embeddingDimension))
        }
    }
}
