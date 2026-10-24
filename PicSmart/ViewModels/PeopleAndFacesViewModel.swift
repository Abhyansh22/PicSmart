//
//  PeopleAndFacesViewModel.swift
//  PicSmart
//

import Photos
import SwiftUI
import Combine
import Observation

enum PeopleFilter: String, CaseIterable, Identifiable {
    case all = "All Faces"
    case portraits = "Portraits"
    case groups = "Groups"
    case blinks = "Blinks / Closed"
    
    var id: String { rawValue }
    
    var iconName: String {
        switch self {
        case .all: return "person.2.fill"
        case .portraits: return "person.crop.square.fill"
        case .groups: return "person.3.sequence.fill"
        case .blinks: return "eye.slash.fill"
        }
    }
}

@Observable
@MainActor
final class PeopleAndFacesViewModel {
    var personClusters: [PersonCluster] = []
    var items: [PersonPhotoItem] = []
    var selectedFilter: PeopleFilter = .all
    var isScanning: Bool = false
    var isRefreshing: Bool = false
    var hasCompletedScan: Bool = false
    var progress: AnalysisProgress?
    var statusMessage: String?
    var selectedIds: Set<String> = []
    var isActive: Bool = false
    
    var onScanCompleted: (() -> Void)?
    
    var favoritePeople: [PersonCluster] {
        personClusters.filter { $0.isFavorite }
    }
    
    var otherPeople: [PersonCluster] {
        personClusters.filter { !$0.isFavorite }
    }
    
    var blinks: [PersonPhotoItem] {
        items.filter { $0.hasBlinkedEyes }
    }
    
    @ObservationIgnored
    private var scanTask: Task<Void, Never>?
    @ObservationIgnored
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        PhotoLibraryService.shared.libraryChangePublisher
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.isActive else { return }
                self.startScan()
            }
            .store(in: &cancellables)
    }
    
    func onAppear() {
        isActive = true
    }
    
    func onDisappear() {
        isActive = false
    }
    
    func startScanIfNeeded() {
        let authStatus = PhotoLibraryService.shared.authorizationStatus
        guard authStatus == .authorized || authStatus == .limited else { return }
        if !isScanning && (!hasCompletedScan || items.isEmpty) {
            startScan()
        }
    }
    
    func startScan() {
        guard !isScanning else { return }
        scanTask?.cancel()
        scanTask = Task {
            await executeScan()
        }
    }
    
    func executeScan() async {
        let authStatus = PhotoLibraryService.shared.authorizationStatus
        guard authStatus == .authorized || authStatus == .limited else {
            isScanning = false
            progress = nil
            statusMessage = nil
            return
        }
        
        isScanning = true
        hasCompletedScan = false
        progress = AnalysisProgress(completed: 0, total: 1, stage: "Checking library…")
        statusMessage = "Analyzing people and faces…"
        
        let result = await PeopleAnalysisEngine.shared.scan { [weak self] prog in
            Task { @MainActor in
                self?.progress = prog
                self?.statusMessage = prog.stage
            }
        }
        
        if !Task.isCancelled {
            self.personClusters = result.personClusters
            self.items = result.allPhotoItems
            self.hasCompletedScan = true
            self.onScanCompleted?()
            
            // Persist to SwiftData
            let clustersToSave = result.personClusters
            Task.detached(priority: .utility) {
                let dtos = clustersToSave.map {
                    PersistedPersonDTO(
                        id: $0.id,
                        name: $0.name,
                        avatarAssetId: $0.avatarAsset.localIdentifier,
                        avatarFaceBoundingBox: $0.avatarFaceBoundingBox,
                        memberAssetIds: $0.assets.map(\.localIdentifier),
                        isFavorite: $0.isFavorite,
                        keyAssetId: $0.keyAssetId
                    )
                }
                try? await PersistentClusterStore.shared.savePersonDTOs(dtos)
            }
        }
        self.isScanning = false
        self.progress = nil
        self.statusMessage = nil
    }
    
    func refresh() async {
        guard !isScanning && !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        
        let result = await PeopleAnalysisEngine.shared.scan()
        guard !Task.isCancelled else { return }
        withAnimation(.snappy) {
            self.personClusters = result.personClusters
            self.items = result.allPhotoItems
            self.hasCompletedScan = true
        }
        self.onScanCompleted?()
        
        let clustersToSave = result.personClusters
        Task.detached(priority: .utility) {
            let dtos = clustersToSave.map {
                PersistedPersonDTO(
                    id: $0.id,
                    name: $0.name,
                    avatarAssetId: $0.avatarAsset.localIdentifier,
                    avatarFaceBoundingBox: $0.avatarFaceBoundingBox,
                    memberAssetIds: $0.assets.map(\.localIdentifier),
                    isFavorite: $0.isFavorite,
                    keyAssetId: $0.keyAssetId
                )
            }
            try? await PersistentClusterStore.shared.savePersonDTOs(dtos)
        }
    }
    
    func cancel() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
        hasCompletedScan = true
        progress = nil
        statusMessage = nil
    }
    
    // MARK: - Cold Launch Hydration
    
    func hydrate(from dtos: [PersistedPersonDTO]) {
        guard personClusters.isEmpty && !hasCompletedScan else { return }
        let allIds = dtos.flatMap { $0.memberAssetIds + [$0.avatarAssetId] }
        guard !allIds.isEmpty else { return }
        
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: allIds, options: nil)
        var map = [String: PHAsset]()
        fetch.enumerateObjects { asset, _, _ in
            map[asset.localIdentifier] = asset
        }
        
        var hydrated: [PersonCluster] = []
        for dto in dtos {
            guard let avatar = map[dto.avatarAssetId] else { continue }
            let members = dto.memberAssetIds.compactMap { map[$0] }
            guard !members.isEmpty else { continue }
            hydrated.append(PersonCluster(
                id: dto.id,
                name: dto.name,
                avatarAsset: avatar,
                avatarFaceBoundingBox: dto.avatarFaceBoundingBox,
                assets: members,
                isFavorite: dto.isFavorite,
                keyAssetId: dto.keyAssetId
            ))
        }
        
        if !hydrated.isEmpty {
            self.personClusters = hydrated
            self.hasCompletedScan = true
            self.onScanCompleted?()
        }
    }
    
    // MARK: - Identity Management
    
    func renamePerson(id: String, newName: String) {
        if let idx = personClusters.firstIndex(where: { $0.id == id }) {
            personClusters[idx].name = newName.trimmingCharacters(in: .whitespaces)
            Task.detached(priority: .utility) {
                try? await PersistentClusterStore.shared.updatePersonName(id: id, newName: newName)
            }
        }
    }
    
    func toggleFavorite(id: String) {
        if let idx = personClusters.firstIndex(where: { $0.id == id }) {
            withAnimation(.snappy) {
                personClusters[idx].isFavorite.toggle()
            }
            Task.detached(priority: .utility) {
                try? await PersistentClusterStore.shared.togglePersonFavorite(id: id)
            }
        }
    }
    
    func removePerson(id: String) {
        withAnimation(.snappy) {
            personClusters.removeAll { $0.id == id }
        }
        Task.detached(priority: .utility) {
            try? await PersistentClusterStore.shared.removePersonCluster(id: id)
        }
    }
    
    // MARK: - Filtered Items
    
    var filteredItems: [PersonPhotoItem] {
        switch selectedFilter {
        case .all:
            return items
        case .portraits:
            return items.filter { $0.isSoloPortrait }
        case .groups:
            return items.filter { $0.isGroupPhoto }
        case .blinks:
            return items.filter { $0.hasBlinkedEyes }
        }
    }
    
    // MARK: - Selection
    
    func toggleSelection(_ assetId: String) {
        if selectedIds.contains(assetId) {
            selectedIds.remove(assetId)
        } else {
            selectedIds.insert(assetId)
        }
    }
    
    func selectAllInFilter() {
        selectedIds = Set(filteredItems.map(\.id))
    }
    
    func deselectAll() {
        selectedIds.removeAll()
    }
    
    var selectedCount: Int {
        selectedIds.count
    }
    
    var selectedSavingsBytes: Int64 {
        items.filter { selectedIds.contains($0.id) }
            .reduce(0) { $0 + $1.fileSize }
    }
    
    var totalCount: Int {
        personClusters.count > 0 ? personClusters.count : items.count
    }
    
    // MARK: - Pruning
    
    func pruneDeletedAssets(_ deletedIds: Set<String>) {
        withAnimation(.snappy) {
            items.removeAll { deletedIds.contains($0.id) }
            selectedIds.subtract(deletedIds)
            
            for i in personClusters.indices.reversed() {
                personClusters[i].assets.removeAll { deletedIds.contains($0.localIdentifier) }
                if personClusters[i].assets.isEmpty {
                    personClusters.remove(at: i)
                }
            }
        }
    }
}
