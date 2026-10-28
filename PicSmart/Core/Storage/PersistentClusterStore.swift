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
    var isFavorite: Bool = false
    var keyAssetId: String? = nil
    var representativeEmbedding: [Float]? = nil
}

struct FaceEmbeddingDTO: Sendable {
    let id: String
    let assetIdentifier: String
    let faceIndex: Int
    let boundingBox: CGRect
    let captureQuality: Float
    let embedding: [Float]
}

@ModelActor
actor PersistentClusterStore {
    static let shared: PersistentClusterStore = {
        do {
            let schema = Schema([
                CachedBlurRecord.self,
                CachedVisualSignature.self,
                PersistentAssetCluster.self,
                CleanupSessionRecord.self,
                PersistentPersonCluster.self,
                CachedFaceEmbedding.self
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
    
    // MARK: - Large Video Metadata Persistence
    
    func saveLargeVideoMetadata(sortedAssetIds: [String], fileSizes: [String: Int64]) throws {
        let catRaw = GalleryCategory.largeVideos.rawValue
        let descriptor = FetchDescriptor<PersistentAssetCluster>(
            predicate: #Predicate { $0.categoryRaw == catRaw }
        )
        let existing = try modelContext.fetch(descriptor)
        for cluster in existing {
            modelContext.delete(cluster)
        }
        
        guard !sortedAssetIds.isEmpty else {
            try modelContext.save()
            return
        }
        
        let cluster = PersistentAssetCluster(
            id: "large_videos_cache",
            categoryRaw: catRaw,
            assetIdentifiers: sortedAssetIds,
            fileSizes: fileSizes
        )
        modelContext.insert(cluster)
        try modelContext.save()
    }
    
    func loadLargeVideoMetadata() throws -> (sortedAssetIds: [String], fileSizes: [String: Int64])? {
        let catRaw = GalleryCategory.largeVideos.rawValue
        let descriptor = FetchDescriptor<PersistentAssetCluster>(
            predicate: #Predicate { $0.categoryRaw == catRaw }
        )
        guard let cluster = try modelContext.fetch(descriptor).first,
              !cluster.assetIdentifiers.isEmpty else { return nil }
        return (cluster.assetIdentifiers, cluster.fileSizes)
    }
    
    // MARK: - Deletion Pruning & Strict Cluster Dissolution
    
    /// Returns all asset identifiers currently participating in any cluster
    func fetchAllTrackedAssetIds() throws -> Set<String> {
        let descriptor = FetchDescriptor<PersistentAssetCluster>()
        let clusters = try modelContext.fetch(descriptor)
        var set = Set<String>()
        for c in clusters {
            set.formUnion(c.assetIdentifiers)
        }
        return set
    }
    
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
            
            // 2. Strict Dissolution Rule: If fewer than 2 assets remain (or empty for large videos), delete cluster!
            let shouldDissolve = (cluster.categoryRaw == GalleryCategory.largeVideos.rawValue) ? cluster.assetIdentifiers.isEmpty : cluster.assetIdentifiers.count < 2
            if shouldDissolve {
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
        
        // Prune blur records for deleted assets
        let blurDescriptor = FetchDescriptor<CachedBlurRecord>()
        if let blurRecords = try? modelContext.fetch(blurDescriptor) {
            for record in blurRecords where deletedIds.contains(record.localIdentifier) {
                modelContext.delete(record)
            }
        }
        
        // Prune face embeddings for deleted assets
        let faceDescriptor = FetchDescriptor<CachedFaceEmbedding>()
        if let faceRecords = try? modelContext.fetch(faceDescriptor) {
            for record in faceRecords where deletedIds.contains(record.assetIdentifier) {
                modelContext.delete(record)
            }
        }
        
        // Prune visual signatures for deleted assets
        let sigDescriptor = FetchDescriptor<CachedVisualSignature>()
        if let sigRecords = try? modelContext.fetch(sigDescriptor) {
            for record in sigRecords where deletedIds.contains(record.localIdentifier) {
                modelContext.delete(record)
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
        // Fetch existing to preserve user custom names, favorites, key photo choices, and embeddings
        let descriptor = FetchDescriptor<PersistentPersonCluster>()
        let existing = try modelContext.fetch(descriptor)
        var nameMap = [String: String]()
        var favMap = [String: Bool]()
        var keyMap = [String: String]()
        var embeddingMap = [String: [Float]]()
        
        // Asset-overlap maps to preserve names/favorites even if cluster indices re-order
        var assetToName = [String: String]()
        var assetToFav = [String: Bool]()
        var assetToKey = [String: String]()
        
        for p in existing {
            if let n = p.name, !n.isEmpty {
                nameMap[p.id] = n
                for aid in p.memberAssetIdentifiers {
                    assetToName[aid] = n
                }
            }
            favMap[p.id] = p.isFavorite
            if p.isFavorite {
                for aid in p.memberAssetIdentifiers {
                    assetToFav[aid] = true
                }
            }
            if let k = p.keyAssetIdentifier {
                keyMap[p.id] = k
                for aid in p.memberAssetIdentifiers {
                    assetToKey[aid] = k
                }
            }
            if let emb = p.representativeEmbedding {
                embeddingMap[p.id] = emb
            }
            modelContext.delete(p)
        }
        
        for dto in persons {
            let directName = nameMap[dto.id] ?? dto.name
            let overlapName = dto.memberAssetIds.compactMap { assetToName[$0] }.first
            let finalName = directName ?? overlapName
            
            let directFav = favMap[dto.id] ?? dto.isFavorite
            let overlapFav = dto.memberAssetIds.contains(where: { assetToFav[$0] == true })
            let finalFav = directFav || overlapFav
            
            let directKey = keyMap[dto.id] ?? dto.keyAssetId
            let overlapKey = dto.memberAssetIds.compactMap { assetToKey[$0] }.first
            let finalKey = directKey ?? overlapKey ?? dto.avatarAssetId
            
            let finalEmbedding = dto.representativeEmbedding ?? embeddingMap[dto.id]
            
            let cluster = PersistentPersonCluster(
                id: dto.id,
                name: finalName,
                avatarAssetIdentifier: finalKey,
                avatarFaceBoundingBox: dto.avatarFaceBoundingBox,
                memberAssetIdentifiers: dto.memberAssetIds,
                isFavorite: finalFav,
                keyAssetIdentifier: finalKey,
                representativeEmbedding: finalEmbedding
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
                memberAssetIds: $0.memberAssetIdentifiers,
                isFavorite: $0.isFavorite,
                keyAssetId: $0.keyAssetIdentifier,
                representativeEmbedding: $0.representativeEmbedding
            )
        }
    }
    
    // MARK: - Incremental Person Updates
    
    func addAssetToPersonCluster(clusterId: String, assetIdentifier: String) throws {
        let descriptor = FetchDescriptor<PersistentPersonCluster>(
            predicate: #Predicate { $0.id == clusterId }
        )
        if let cluster = try modelContext.fetch(descriptor).first {
            if !cluster.memberAssetIdentifiers.contains(assetIdentifier) {
                cluster.memberAssetIdentifiers.append(assetIdentifier)
                cluster.updatedAt = Date()
                try modelContext.save()
            }
        }
    }
    
    func insertNewPersonCluster(dto: PersistedPersonDTO) throws {
        let cluster = PersistentPersonCluster(
            id: dto.id,
            name: dto.name,
            avatarAssetIdentifier: dto.avatarAssetId,
            avatarFaceBoundingBox: dto.avatarFaceBoundingBox,
            memberAssetIdentifiers: dto.memberAssetIds,
            isFavorite: dto.isFavorite,
            keyAssetIdentifier: dto.keyAssetId ?? dto.avatarAssetId,
            representativeEmbedding: dto.representativeEmbedding
        )
        modelContext.insert(cluster)
        try modelContext.save()
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
    
    func togglePersonFavorite(id: String) throws {
        let descriptor = FetchDescriptor<PersistentPersonCluster>(
            predicate: #Predicate { $0.id == id }
        )
        if let person = try modelContext.fetch(descriptor).first {
            person.isFavorite.toggle()
            try modelContext.save()
        }
    }
    
    func removePersonCluster(id: String) throws {
        let descriptor = FetchDescriptor<PersistentPersonCluster>(
            predicate: #Predicate { $0.id == id }
        )
        if let person = try modelContext.fetch(descriptor).first {
            modelContext.delete(person)
            try modelContext.save()
        }
    }
    
    // MARK: - Face Embedding Cache Persistence
    
    func saveFaceEmbeddings(_ embeddings: [FaceEmbeddingDTO]) throws {
        guard !embeddings.isEmpty else { return }
        for dto in embeddings {
            let entity = CachedFaceEmbedding(
                id: dto.id,
                assetIdentifier: dto.assetIdentifier,
                faceIndex: dto.faceIndex,
                boundingBox: dto.boundingBox,
                captureQuality: dto.captureQuality,
                embedding: dto.embedding
            )
            modelContext.insert(entity)
        }
        try modelContext.save()
    }
    
    func loadAllFaceEmbeddings() throws -> [FaceEmbeddingDTO] {
        let descriptor = FetchDescriptor<CachedFaceEmbedding>()
        let records = try modelContext.fetch(descriptor)
        return records.map {
            FaceEmbeddingDTO(
                id: $0.id,
                assetIdentifier: $0.assetIdentifier,
                faceIndex: $0.faceIndex,
                boundingBox: $0.boundingBox,
                captureQuality: $0.captureQuality,
                embedding: $0.embedding
            )
        }
    }
    
    func loadFaceEmbeddings(for assetIdentifiers: Set<String>) throws -> [String: [FaceEmbeddingDTO]] {
        guard !assetIdentifiers.isEmpty else { return [:] }
        let all = try loadAllFaceEmbeddings()
        var grouped: [String: [FaceEmbeddingDTO]] = [:]
        for item in all where assetIdentifiers.contains(item.assetIdentifier) {
            grouped[item.assetIdentifier, default: []].append(item)
        }
        return grouped
    }
    
    // MARK: - Blur Records Persistence
    
    func saveBlurRecords(_ records: [BlurRecordDTO]) throws {
        guard !records.isEmpty else { return }
        for dto in records {
            let entity = CachedBlurRecord(
                localIdentifier: dto.localIdentifier,
                blurPercentage: dto.blurPercentage,
                isSevere: dto.isSevere,
                evaluatedAt: dto.evaluatedAt,
                modificationTime: dto.modificationTime
            )
            modelContext.insert(entity)
        }
        try modelContext.save()
    }
    
    func loadAllBlurRecords() throws -> [String: BlurRecordDTO] {
        var descriptor = FetchDescriptor<CachedBlurRecord>()
        descriptor.propertiesToFetch = [
            \.localIdentifier,
            \.blurPercentage,
            \.isSevere,
            \.evaluatedAt,
            \.modificationTime
        ]
        guard let records = try? modelContext.fetch(descriptor) else { return [:] }
        var map = [String: BlurRecordDTO]()
        map.reserveCapacity(records.count)
        for r in records {
            map[r.localIdentifier] = BlurRecordDTO(
                localIdentifier: r.localIdentifier,
                blurPercentage: r.blurPercentage,
                isSevere: r.isSevere,
                evaluatedAt: r.evaluatedAt,
                modificationTime: r.modificationTime
            )
        }
        return map
    }
    
    func clearBlurRecords() throws {
        try modelContext.delete(model: CachedBlurRecord.self)
        try modelContext.save()
    }
}
