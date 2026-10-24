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
    var updatedAt: Date
    
    init(
        id: String,
        name: String? = nil,
        avatarAssetIdentifier: String,
        avatarFaceBoundingBox: CGRect,
        memberAssetIdentifiers: [String],
        isFavorite: Bool = false,
        keyAssetIdentifier: String? = nil
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
        self.updatedAt = Date()
    }
    
    var avatarFaceBoundingBox: CGRect {
        CGRect(x: avatarFaceX, y: avatarFaceY, width: avatarFaceWidth, height: avatarFaceHeight)
    }
}
