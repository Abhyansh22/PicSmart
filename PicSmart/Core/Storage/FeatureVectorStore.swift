//
//  FeatureVectorStore.swift
//  PicSmart
//

import Foundation
import SwiftData
import Vision

// MARK: - SwiftData Model

@Model
final class CachedVisualSignature {
    @Attribute(.unique) var localIdentifier: String
    @Attribute(.externalStorage) var featureData: Data?
    var gradientHash: UInt64
    var averageLuminance: UInt8
    var aspectBand: Int
    var creationWeekBucket: Int64
    var sharpnessScore: Double
    var modificationTime: TimeInterval
    
    init(
        localIdentifier: String,
        featureData: Data? = nil,
        gradientHash: UInt64,
        averageLuminance: UInt8,
        aspectBand: Int,
        creationWeekBucket: Int64,
        sharpnessScore: Double = 0.0,
        modificationTime: TimeInterval = 0
    ) {
        self.localIdentifier = localIdentifier
        self.featureData = featureData
        self.gradientHash = gradientHash
        self.averageLuminance = averageLuminance
        self.aspectBand = aspectBand
        self.creationWeekBucket = creationWeekBucket
        self.sharpnessScore = sharpnessScore
        self.modificationTime = modificationTime
    }
}

// MARK: - Sendable DTO for Crossing Actor Boundaries

struct VisualSignatureDTO: Sendable {
    let localIdentifier: String
    let gradientHash: UInt64
    let averageLuminance: UInt8
    let aspectBand: Int
    let creationWeekBucket: Int64
    let sharpnessScore: Double
    let featureData: Data?
    
    var observation: VNFeaturePrintObservation? {
        guard let data = featureData else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: data)
    }
}

// MARK: - SwiftData ModelActor

@ModelActor
actor FeatureVectorStore {
    static let shared: FeatureVectorStore = {
        do {
            let schema = Schema([
                CachedVisualSignature.self,
                PersistentAssetCluster.self,
                CleanupSessionRecord.self
            ])
            let config = ModelConfiguration("PicSmartVisualStore", isStoredInMemoryOnly: false)
            let container = try ModelContainer(for: schema, configurations: [config])
            return FeatureVectorStore(modelContainer: container)
        } catch {
            fatalError("Failed to initialize ModelContainer for FeatureVectorStore: \(error)")
        }
    }()
    
    /// Loads all cached signatures as lightweight DTOs without faulting heavy blob data unless requested.
    func loadAllSignatures() -> [String: VisualSignatureDTO] {
        var descriptor = FetchDescriptor<CachedVisualSignature>()
        descriptor.propertiesToFetch = [
            \.localIdentifier,
            \.gradientHash,
            \.averageLuminance,
            \.aspectBand,
            \.creationWeekBucket,
            \.sharpnessScore
        ]
        
        guard let models = try? modelContext.fetch(descriptor) else { return [:] }
        var map = [String: VisualSignatureDTO]()
        map.reserveCapacity(models.count)
        
        for model in models {
            map[model.localIdentifier] = VisualSignatureDTO(
                localIdentifier: model.localIdentifier,
                gradientHash: model.gradientHash,
                averageLuminance: model.averageLuminance,
                aspectBand: model.aspectBand,
                creationWeekBucket: model.creationWeekBucket,
                sharpnessScore: model.sharpnessScore,
                featureData: model.featureData
            )
        }
        return map
    }
    
    /// Saves a batch of visual signatures to disk in a single transaction.
    func saveSignatures(_ items: [VisualSignatureDTO]) {
        guard !items.isEmpty else { return }
        
        for item in items {
            let model = CachedVisualSignature(
                localIdentifier: item.localIdentifier,
                featureData: item.featureData,
                gradientHash: item.gradientHash,
                averageLuminance: item.averageLuminance,
                aspectBand: item.aspectBand,
                creationWeekBucket: item.creationWeekBucket,
                sharpnessScore: item.sharpnessScore
            )
            modelContext.insert(model)
        }
        
        try? modelContext.save()
    }
    
    /// Updates feature data for an existing signature.
    func updateFeatureData(for id: String, data: Data) {
        let descriptor = FetchDescriptor<CachedVisualSignature>(
            predicate: #Predicate { $0.localIdentifier == id }
        )
        if let models = try? modelContext.fetch(descriptor), let model = models.first {
            model.featureData = data
            try? modelContext.save()
        }
    }
    
    /// Removes signatures for deleted assets.
    func remove(identifiers: [String]) {
        guard !identifiers.isEmpty else { return }
        let idSet = Set(identifiers)
        let descriptor = FetchDescriptor<CachedVisualSignature>()
        guard let models = try? modelContext.fetch(descriptor) else { return }
        for model in models where idSet.contains(model.localIdentifier) {
            modelContext.delete(model)
        }
        try? modelContext.save()
    }
    
    /// Clears the store.
    func clear() {
        try? modelContext.delete(model: CachedVisualSignature.self)
        try? modelContext.save()
    }
}
