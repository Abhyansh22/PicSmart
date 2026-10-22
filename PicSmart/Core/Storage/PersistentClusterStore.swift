//
//  PersistentClusterStore.swift
//  PicSmart
//

import Foundation
import SwiftData
import Photos

struct PersistedGroupDTO: Sendable {
    let id: String
    let assetIds: [String]
    let keeperId: String?
    let bestShotId: String?
    let markedForDeletionIds: [String]?
    let fileSizes: [String: Int64]
    let similarityScore: Float
}

struct PersistedPersonDTO: Sendable {
    let id: String
    let name: String?
    let avatarAssetId: String
    let avatarFaceBoundingBox: CGRect
    let memberAssetIds: [String]
}

@ModelActor
actor PersistentClusterStore {
    static let shared: PersistentClusterStore = {
        do {
            let schema = Schema([
                CachedVisualSignature.self,
                PersistentAssetCluster.self,
                CleanupSessionRecord.self,
                PersistentPersonCluster.self
            ])
            let config = ModelConfiguration("PicSmartVisualStore", isStoredInMemoryOnly: false)
            let container = try ModelContainer(for: schema, configurations: [config])
            return PersistentClusterStore(modelContainer: container)
        } catch {
            fatalError("Failed to initialize SwiftData container: \(error)")
        }
    }()
    
    // MARK: - Save Analyzed Clusters
    
    func saveClusters(_ groups: [AssetGroup], for category: GalleryCategory) throws {
        let catRaw = category.rawValue
        
        // Remove existing clusters for this category
        let descriptor = FetchDescriptor<PersistentAssetCluster>(
            predicate: #Predicate { $0.categoryRaw == catRaw }
        )
        let existing = try modelContext.fetch(descriptor)
        for cluster in existing {
            modelContext.delete(cluster)
        }
        
        // Insert new clusters
        for group in groups {
            guard group.assets.count >= 2 else { continue }
            let cluster = PersistentAssetCluster(
                id: group.id,
                categoryRaw: category.rawValue,
                assetIdentifiers: group.assets.map(\.localIdentifier),
                keeperIdentifier: group.keeperId,
                bestShotIdentifier: group.bestShotId,
                markedForDeletionIdentifiers: Array(group.markedForDeletionIds),
                similarityScore: group.similarityScore ?? 0.85,
                fileSizes: group.fileSizes
            )
            modelContext.insert(cluster)
        }
        try modelContext.save()
    }
    
    // MARK: - Cold Launch Hydration
    
    func loadClusters(for category: GalleryCategory) throws -> [PersistedGroupDTO] {
        let catRaw = category.rawValue
        let descriptor = FetchDescriptor<PersistentAssetCluster>(
            predicate: #Predicate { $0.categoryRaw == catRaw },
            sortBy: [SortDescriptor(\.id)]
        )
        let records = try modelContext.fetch(descriptor)
        
        return records.compactMap { cluster in
            guard cluster.assetIdentifiers.count >= 2 else { return nil }
            return PersistedGroupDTO(
                id: cluster.id,
                assetIds: cluster.assetIdentifiers,
                keeperId: cluster.keeperIdentifier,
                bestShotId: cluster.bestShotIdentifier,
                markedForDeletionIds: cluster.markedForDeletionIdentifiers,
                fileSizes: cluster.fileSizes,
                similarityScore: cluster.similarityScore
            )
        }
    }
    
    // MARK: - Deletion Pruning & Strict Cluster Dissolution
    
    /// Prunes deleted identifiers across all SwiftData clusters.
    /// If a cluster drops below 2 photos, it is dissolved and permanently deleted from SwiftData.
    func pruneDeletedAssets(_ deletedIds: Set<String>) throws {
        guard !deletedIds.isEmpty else { return }
        
        let descriptor = FetchDescriptor<PersistentAssetCluster>()
        let allClusters = try modelContext.fetch(descriptor)
        
        for cluster in allClusters {
            let hasOverlap = cluster.assetIdentifiers.contains { deletedIds.contains($0) }
            guard hasOverlap else { continue }
            
            // 1. Remove deleted identifiers
            cluster.assetIdentifiers.removeAll { deletedIds.contains($0) }
            
            // 2. Strict Dissolution Rule: If fewer than 2 assets remain, delete cluster!
            if cluster.assetIdentifiers.count < 2 {
                modelContext.delete(cluster)
            } else {
                // 3. Keeper and BestShot Fallback
                if let keeper = cluster.keeperIdentifier, deletedIds.contains(keeper) {
                    cluster.keeperIdentifier = cluster.assetIdentifiers.first
                }
                if let bestShot = cluster.bestShotIdentifier, deletedIds.contains(bestShot) {
                    cluster.bestShotIdentifier = cluster.keeperIdentifier ?? cluster.assetIdentifiers.first
                }
                
                // Prune file size dictionary
                var sizes = cluster.fileSizes
                for id in deletedIds { sizes.removeValue(forKey: id) }
                cluster.fileSizesJSON = try? JSONEncoder().encode(sizes)
                cluster.updatedAt = Date()
            }
        }
        
        try modelContext.save()
    }
    
    // MARK: - Cleanup History & Reclaimed Storage
    
    func recordCleanup(categoryTitle: String, itemCount: Int, bytesSaved: Int64, sampleIdentifiers: [String]) throws {
        let record = CleanupSessionRecord(
            categoryTitle: categoryTitle,
            itemCount: itemCount,
            bytesSaved: bytesSaved,
            sampleIdentifiers: sampleIdentifiers
        )
        modelContext.insert(record)
        try modelContext.save()
    }
    
    func fetchCleanupHistory() throws -> [(id: UUID, date: Date, categoryTitle: String, itemCount: Int, bytesSaved: Int64, sampleIds: [String])] {
        let descriptor = FetchDescriptor<CleanupSessionRecord>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let records = try modelContext.fetch(descriptor)
        return records.map {
            ($0.id, $0.date, $0.categoryTitle, $0.itemCount, $0.bytesSaved, $0.sampleLocalIdentifiers)
        }
    }
    
    func totalLifetimeBytesSaved() throws -> Int64 {
        let descriptor = FetchDescriptor<CleanupSessionRecord>()
        let records = try modelContext.fetch(descriptor)
        return records.reduce(0) { $0 + $1.bytesSaved }
    }
    
    // MARK: - Person & Face Clusters
    
    func savePersonDTOs(_ persons: [PersistedPersonDTO]) throws {
        // Fetch existing to preserve user custom names
        let descriptor = FetchDescriptor<PersistentPersonCluster>()
        let existing = try modelContext.fetch(descriptor)
        var nameMap = [String: String]()
        for p in existing {
            if let n = p.name, !n.isEmpty {
                nameMap[p.id] = n
            }
            modelContext.delete(p)
        }
        
        for dto in persons {
            let cluster = PersistentPersonCluster(
                id: dto.id,
                name: nameMap[dto.id] ?? dto.name,
                avatarAssetIdentifier: dto.avatarAssetId,
                avatarFaceBoundingBox: dto.avatarFaceBoundingBox,
                memberAssetIdentifiers: dto.memberAssetIds
            )
            modelContext.insert(cluster)
        }
        try modelContext.save()
    }
    
    func loadPersonDTOs() throws -> [PersistedPersonDTO] {
        let descriptor = FetchDescriptor<PersistentPersonCluster>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        let records = try modelContext.fetch(descriptor)
        return records.map {
            PersistedPersonDTO(
                id: $0.id,
                name: $0.name,
                avatarAssetId: $0.avatarAssetIdentifier,
                avatarFaceBoundingBox: $0.avatarFaceBoundingBox,
                memberAssetIds: $0.memberAssetIdentifiers
            )
        }
    }
    
    func updatePersonName(id: String, newName: String) throws {
        let descriptor = FetchDescriptor<PersistentPersonCluster>(
            predicate: #Predicate { $0.id == id }
        )
        if let person = try modelContext.fetch(descriptor).first {
            person.name = newName.trimmingCharacters(in: .whitespaces)
            try modelContext.save()
        }
    }
}
