//
//  CachedBlurRecord.swift
//  PicSmart
//

import Foundation
import SwiftData

@Model
final class CachedBlurRecord {
    @Attribute(.unique) var localIdentifier: String
    var blurPercentage: Int        // 0 = sharp photo; 40...99 = blur severity percentage
    var isSevere: Bool             // blurPercentage >= 75
    var evaluatedAt: Date
    var modificationTime: TimeInterval

    init(
        localIdentifier: String,
        blurPercentage: Int,
        isSevere: Bool,
        evaluatedAt: Date = Date(),
        modificationTime: TimeInterval = 0
    ) {
        self.localIdentifier = localIdentifier
        self.blurPercentage = blurPercentage
        self.isSevere = isSevere
        self.evaluatedAt = evaluatedAt
        self.modificationTime = modificationTime
    }
}

public struct BlurRecordDTO: Sendable {
    public let localIdentifier: String
    public let blurPercentage: Int
    public let isSevere: Bool
    public let evaluatedAt: Date
    public let modificationTime: TimeInterval
    
    public init(
        localIdentifier: String,
        blurPercentage: Int,
        isSevere: Bool,
        evaluatedAt: Date = Date(),
        modificationTime: TimeInterval = 0
    ) {
        self.localIdentifier = localIdentifier
        self.blurPercentage = blurPercentage
        self.isSevere = isSevere
        self.evaluatedAt = evaluatedAt
        self.modificationTime = modificationTime
    }
}
