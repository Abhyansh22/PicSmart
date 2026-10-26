//
//  PersistentPersonCluster.swift
//  PicSmart
//

import Foundation
import SwiftData
import CoreGraphics

/// SwiftData persistent model storing recognized people and face identity clusters.
@Model
final class PersistentPersonCluster {
    @Attribute(.unique) var id: String
    var name: String?
    var avatarAssetIdentifier: String
    var avatarFaceX: Double
    var avatarFaceY: Double
    var avatarFaceWidth: Double
    var avatarFaceHeight: Double
    var memberAssetIdentifiers: [String]
    var isFavorite: Bool
    var keyAssetIdentifier: String?
    @Attribute(.externalStorage) var representativeEmbeddingData: Data?
    var updatedAt: Date
    
    init(
        id: String,
        name: String? = nil,
        avatarAssetIdentifier: String,
        avatarFaceBoundingBox: CGRect,
        memberAssetIdentifiers: [String],
        isFavorite: Bool = false,
        keyAssetIdentifier: String? = nil,
        representativeEmbedding: [Float]? = nil
    ) {
        self.id = id
        self.name = name
        self.avatarAssetIdentifier = avatarAssetIdentifier
        self.avatarFaceX = Double(avatarFaceBoundingBox.origin.x)
        self.avatarFaceY = Double(avatarFaceBoundingBox.origin.y)
        self.avatarFaceWidth = Double(avatarFaceBoundingBox.size.width)
        self.avatarFaceHeight = Double(avatarFaceBoundingBox.size.height)
        self.memberAssetIdentifiers = memberAssetIdentifiers
        self.isFavorite = isFavorite
        self.keyAssetIdentifier = keyAssetIdentifier
        
        if let embedding = representativeEmbedding, !embedding.isEmpty {
            self.representativeEmbeddingData = embedding.withUnsafeBufferPointer { buffer in
                Data(buffer: buffer)
            }
        } else {
            self.representativeEmbeddingData = nil
        }
        
        self.updatedAt = Date()
    }
    
    var avatarFaceBoundingBox: CGRect {
        CGRect(x: avatarFaceX, y: avatarFaceY, width: avatarFaceWidth, height: avatarFaceHeight)
    }
    
    var representativeEmbedding: [Float]? {
        guard let data = representativeEmbeddingData,
              data.count >= 128 * MemoryLayout<Float>.size else { return nil }
        return data.withUnsafeBytes { rawBuffer in
            Array(rawBuffer.bindMemory(to: Float.self).prefix(128))
        }
    }
}
