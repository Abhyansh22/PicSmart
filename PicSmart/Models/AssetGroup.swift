//
//  AssetGroup.swift
//  PicSmart
//

import Photos
import Foundation

struct AssetGroup: Identifiable, Sendable {
    let id: String
    var assets: [PHAsset]
    var keeperId: String?
    var bestShotId: String?
    var fileSizes: [String: Int64] = [:]
    var similarityScore: Float?
    var markedForDeletionIds: Set<String>
    
    init(
        id: String,
        assets: [PHAsset],
        keeperId: String? = nil,
        bestShotId: String? = nil,
        fileSizes: [String: Int64] = [:],
        similarityScore: Float? = nil,
        markedForDeletionIds: Set<String>? = nil
    ) {
        self.id = id
        self.assets = assets
        self.keeperId = keeperId
        self.bestShotId = bestShotId
        self.fileSizes = fileSizes
        self.similarityScore = similarityScore
        
        if let explicit = markedForDeletionIds {
            self.markedForDeletionIds = explicit
        } else {
            // Default: Mark all non-keepers for deletion
            let keeper = keeperId ?? assets.first?.localIdentifier
            self.markedForDeletionIds = Set(assets.filter { $0.localIdentifier != keeper }.map(\.localIdentifier))
        }
    }
    
    var totalBytes: Int64 {
        assets.reduce(0) { sum, asset in
            sum + (fileSizes[asset.localIdentifier] ?? 0)
        }
    }
    
    var markedAssets: [PHAsset] {
        assets.filter { markedForDeletionIds.contains($0.localIdentifier) }
    }
    
    var savingsBytes: Int64 {
        markedAssets.reduce(0) { $0 + (fileSizes[$1.localIdentifier] ?? 0) }
    }
    
    var nonKeepers: [PHAsset] {
        guard let keeperId = keeperId ?? assets.first?.localIdentifier else { return [] }
        return assets.filter { $0.localIdentifier != keeperId }
    }
}

struct AnalysisProgress: Sendable {
    let completed: Int
    let total: Int
    let stage: String
    
    var fractionCompleted: Double {
        total > 0 ? min(1.0, Double(completed) / Double(total)) : 0
    }
}
