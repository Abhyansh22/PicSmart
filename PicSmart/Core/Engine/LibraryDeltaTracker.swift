//
//  LibraryDeltaTracker.swift
//  PicSmart
//

import Photos
import Foundation

struct DeltaSyncResult: Sendable {
    let addedAssets: [PHAsset]
    let deletedAssetIds: Set<String>
    let isInitialRun: Bool
}

actor LibraryDeltaTracker {
    static let shared = LibraryDeltaTracker()
    
    private static let lastCreationDateKey = "picsmart.delta.lastCreationDate"
    private static let lastAssetCountKey = "picsmart.delta.lastAssetCount"
    
    private init() {}
    
    /// Checks for added or deleted media assets since last session checkpoint
    func checkForDeltas() async -> DeltaSyncResult {
        let authStatus = await MainActor.run {
            PhotoLibraryService.shared.authorizationStatus
        }
        guard authStatus == .authorized || authStatus == .limited else {
            return DeltaSyncResult(addedAssets: [], deletedAssetIds: [], isInitialRun: false)
        }
        
        let defaults = UserDefaults.standard
        let storedTimestamp = defaults.double(forKey: Self.lastCreationDateKey)
        let storedCount = defaults.integer(forKey: Self.lastAssetCountKey)
        
        let allOptions = PHFetchOptions()
        allOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let allAssets = PHAsset.fetchAssets(with: allOptions)
        let currentTotalCount = allAssets.count
        
        guard currentTotalCount > 0 else {
            defaults.set(0.0, forKey: Self.lastCreationDateKey)
            defaults.set(0, forKey: Self.lastAssetCountKey)
            return DeltaSyncResult(addedAssets: [], deletedAssetIds: [], isInitialRun: false)
        }
        
        let newestAsset = allAssets.firstObject
        let newestDate = newestAsset?.creationDate?.timeIntervalSince1970 ?? 0.0
        
        // Initial cold baseline check
        if storedTimestamp <= 0.0 || storedCount <= 0 {
            defaults.set(newestDate, forKey: Self.lastCreationDateKey)
            defaults.set(currentTotalCount, forKey: Self.lastAssetCountKey)
            return DeltaSyncResult(addedAssets: [], deletedAssetIds: [], isInitialRun: true)
        }
        
        var addedAssets: [PHAsset] = []
        var deletedAssetIds = Set<String>()
        
        // 1. Detect Newly Added Assets (creationDate > storedTimestamp)
        if newestDate > storedTimestamp {
            let deltaOptions = PHFetchOptions()
            let thresholdDate = Date(timeIntervalSince1970: storedTimestamp)
            deltaOptions.predicate = NSPredicate(format: "creationDate > %@", thresholdDate as NSDate)
            deltaOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            
            let deltaFetch = PHAsset.fetchAssets(with: deltaOptions)
            deltaFetch.enumerateObjects { asset, _, _ in
                addedAssets.append(asset)
            }
        }
        
        // 2. Detect Deleted Assets from Persisted Clusters
        let trackedIds = (try? await PersistentClusterStore.shared.fetchAllTrackedAssetIds()) ?? []
        if !trackedIds.isEmpty {
            let checkFetch = PHAsset.fetchAssets(withLocalIdentifiers: Array(trackedIds), options: nil)
            var existingIds = Set<String>()
            checkFetch.enumerateObjects { asset, _, _ in
                existingIds.insert(asset.localIdentifier)
            }
            deletedAssetIds = trackedIds.subtracting(existingIds)
        }
        
        // 3. Update Checkpoint
        defaults.set(newestDate, forKey: Self.lastCreationDateKey)
        defaults.set(currentTotalCount, forKey: Self.lastAssetCountKey)
        
        return DeltaSyncResult(
            addedAssets: addedAssets,
            deletedAssetIds: deletedAssetIds,
            isInitialRun: false
        )
    }
    
    /// Resets checkpoints if needed
    func resetCheckpoints() {
        UserDefaults.standard.removeObject(forKey: Self.lastCreationDateKey)
        UserDefaults.standard.removeObject(forKey: Self.lastAssetCountKey)
    }
}
