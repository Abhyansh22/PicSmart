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
    
    var totalBytes: Int64 {
        assets.reduce(0) { sum, asset in
            sum + (fileSizes[asset.localIdentifier] ?? 0)
        }
    }
    
    var savingsBytes: Int64 {
        guard let keeperId = keeperId ?? assets.first?.localIdentifier else { return 0 }
        let keeperBytes = fileSizes[keeperId] ?? 0
        return max(0, totalBytes - keeperBytes)
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
