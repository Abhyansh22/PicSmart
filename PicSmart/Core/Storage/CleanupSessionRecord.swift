//
//  CleanupSessionRecord.swift
//  PicSmart
//

import Foundation
import SwiftData

/// SwiftData model tracking media cleanup history, storage reclaimed, and sample previews.
@Model
final class CleanupSessionRecord {
    @Attribute(.unique) var id: UUID
    var date: Date
    var categoryTitle: String
    var itemCount: Int
    var bytesSaved: Int64
    var sampleLocalIdentifiers: [String]
    
    init(categoryTitle: String, itemCount: Int, bytesSaved: Int64, sampleIdentifiers: [String]) {
        self.id = UUID()
        self.date = Date()
        self.categoryTitle = categoryTitle
        self.itemCount = itemCount
        self.bytesSaved = bytesSaved
        self.sampleLocalIdentifiers = sampleIdentifiers
    }
}
