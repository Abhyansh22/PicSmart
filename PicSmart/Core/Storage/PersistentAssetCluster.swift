//
//  PersistentAssetCluster.swift
//  PicSmart
//

import Foundation
import SwiftData

/// SwiftData persistent model storing analyzed media clusters across app cold launches.
@Model
final class PersistentAssetCluster {
    @Attribute(.unique) var id: String
    var categoryRaw: String
    var assetIdentifiers: [String]
    var keeperIdentifier: String?
    var bestShotIdentifier: String?
    var markedForDeletionIdentifiers: [String]?
    var similarityScore: Float
    var fileSizesJSON: Data?
    var updatedAt: Date
    
    init(
        id: String,
        categoryRaw: String,
        assetIdentifiers: [String],
        keeperIdentifier: String? = nil,
        bestShotIdentifier: String? = nil,
        markedForDeletionIdentifiers: [String]? = nil,
        similarityScore: Float = 0.85,
        fileSizes: [String: Int64] = [:]
    ) {
        self.id = id
        self.categoryRaw = categoryRaw
        self.assetIdentifiers = assetIdentifiers
        self.keeperIdentifier = keeperIdentifier
        self.bestShotIdentifier = bestShotIdentifier
        self.markedForDeletionIdentifiers = markedForDeletionIdentifiers
        self.similarityScore = similarityScore
        self.fileSizesJSON = try? JSONEncoder().encode(fileSizes)
        self.updatedAt = Date()
    }
    
    var fileSizes: [String: Int64] {
        guard let data = fileSizesJSON else { return [:] }
        return (try? JSONDecoder().decode([String: Int64].self, from: data)) ?? [:]
    }
}
