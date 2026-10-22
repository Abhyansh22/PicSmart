//
//  PhotoLibraryService.swift
//  PicSmart
//

import UIKit
import Photos
import Combine
import Observation

@Observable
@MainActor
final class PhotoLibraryService: NSObject {
    static let shared = PhotoLibraryService()
    
    var authorizationStatus: PHAuthorizationStatus = .notDetermined
    
    @ObservationIgnored
    let libraryChangePublisher = PassthroughSubject<PHChange, Never>()
    
    @ObservationIgnored
    private var isObserverRegistered = false
    
    override init() {
        super.init()
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        self.authorizationStatus = status
        registerObserverIfNeeded()
    }
    
    deinit {
        if isObserverRegistered {
            PHPhotoLibrary.shared().unregisterChangeObserver(self)
        }
    }
    
    func registerObserverIfNeeded() {
        guard !isObserverRegistered else { return }
        if authorizationStatus == .authorized || authorizationStatus == .limited {
            PHPhotoLibrary.shared().register(self)
            isObserverRegistered = true
        }
    }
    
    func checkAuthorization() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        authorizationStatus = status
        registerObserverIfNeeded()
    }
    
    func requestAuthorization() async -> PHAuthorizationStatus {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        self.authorizationStatus = status
        registerObserverIfNeeded()
        return status
    }
    
    // MARK: - Zero-Copy Database Cursor Queries
    
    nonisolated func fetchScreenshotsCursor() -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "(mediaSubtypes & %d) != 0",
            PHAssetMediaSubtype.photoScreenshot.rawValue
        )
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        return PHAsset.fetchAssets(with: .image, options: options)
    }
    
    nonisolated func fetchVideosCursor() -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        return PHAsset.fetchAssets(with: .video, options: options)
    }
    
    nonisolated func fetchScreenshotsCount() -> Int {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "(mediaSubtypes & %d) != 0",
            PHAssetMediaSubtype.photoScreenshot.rawValue
        )
        return PHAsset.fetchAssets(with: .image, options: options).count
    }
    
    nonisolated func fetchVideosCount() -> Int {
        let options = PHFetchOptions()
        return PHAsset.fetchAssets(with: .video, options: options).count
    }
    
    nonisolated func fetchPeopleAndPortraitsCursor() -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "(mediaSubtypes & %d) != 0",
            PHAssetMediaSubtype.photoDepthEffect.rawValue
        )
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        return PHAsset.fetchAssets(with: .image, options: options)
    }
    
    nonisolated func fetchPeopleAndPortraitsCount() -> Int {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "(mediaSubtypes & %d) != 0",
            PHAssetMediaSubtype.photoDepthEffect.rawValue
        )
        return PHAsset.fetchAssets(with: .image, options: options).count
    }
    
    // MARK: - Safe Deletion
    
    func deleteAssets(localIdentifiers: [String]) async throws -> Set<String> {
        guard !localIdentifiers.isEmpty else { return [] }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: localIdentifiers, options: nil)
        guard result.count > 0 else { return [] }
        
        var deletedIds = Set<String>()
        result.enumerateObjects { asset, _, _ in
            deletedIds.insert(asset.localIdentifier)
        }
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(result)
            } completionHandler: { success, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: NSError(domain: "PicSmart", code: -1, userInfo: [NSLocalizedDescriptionKey: "Deletion was cancelled or failed"]))
                }
            }
        }
        
        return deletedIds
    }
}

// MARK: - PHPhotoLibraryChangeObserver
extension PhotoLibraryService: PHPhotoLibraryChangeObserver {
    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in
            self.libraryChangePublisher.send(changeInstance)
        }
    }
}
