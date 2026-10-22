//
//  PeopleAndFacesViewModel.swift
//  PicSmart
//

import Photos
import SwiftUI
import Combine
import Observation

enum PeopleFilter: String, CaseIterable, Identifiable {
    case all = "All People"
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
            self.items = result
            self.hasCompletedScan = true
            self.onScanCompleted?()
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
            self.items = result
            self.hasCompletedScan = true
        }
        self.onScanCompleted?()
    }
    
    func cancel() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
        hasCompletedScan = true
        progress = nil
        statusMessage = nil
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
        items.count
    }
    
    // MARK: - Pruning
    
    func pruneDeletedAssets(_ deletedIds: Set<String>) {
        withAnimation(.snappy) {
            items.removeAll { deletedIds.contains($0.id) }
            selectedIds.subtract(deletedIds)
        }
    }
}
