//
//  BlurredPhotosViewModel.swift
//  PicSmart
//

import Photos
import SwiftUI
import Combine
import Observation

enum BlurFilterTab: String, CaseIterable, Identifiable {
    case all = "All"
    case severe = "Severe"
    case soft = "Soft Focus"
    
    var id: String { rawValue }
}

@Observable
@MainActor
final class BlurredPhotosViewModel {
    var items: [BlurredPhotoItem] = []
    var selectedTab: BlurFilterTab = .all
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
                guard let self else { return }
                if self.isActive {
                    self.startScan()
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Filtered Properties
    
    var filteredItems: [BlurredPhotoItem] {
        switch selectedTab {
        case .all:
            return items
        case .severe:
            return items.filter { $0.isSevere }
        case .soft:
            return items.filter { !$0.isSevere }
        }
    }
    
    var severeCount: Int {
        items.filter { $0.isSevere }.count
    }
    
    var softCount: Int {
        items.filter { !$0.isSevere }.count
    }
    
    var totalPotentialSavingsBytes: Int64 {
        items.reduce(0) { $0 + $1.fileSize }
    }
    
    /// Incremental insertion of a newly discovered blurred photo
    func appendItem(_ item: BlurredPhotoItem) {
        guard !items.contains(where: { $0.id == item.id }) else { return }
        withAnimation(.snappy) {
            self.items.insert(item, at: 0)
            self.items.sort { $0.blurPercentage > $1.blurPercentage }
        }
        self.onScanCompleted?()
    }
    
    // MARK: - Cold Launch Hydration
    
    func hydrate(from hydratedItems: [BlurredPhotoItem]) {
        guard items.isEmpty && !hasCompletedScan else { return }
        guard !hydratedItems.isEmpty else { return }
        
        self.items = hydratedItems
        self.hasCompletedScan = true
        self.onScanCompleted?()
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
        statusMessage = "Analyzing photo sharpness…"
        
        let result = await BlurredPhotosFunnel.shared.scan { [weak self] prog in
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
        
        let result = await BlurredPhotosFunnel.shared.scan()
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
    
    // MARK: - Selection
    
    func toggleSelection(_ assetId: String) {
        if selectedIds.contains(assetId) {
            selectedIds.remove(assetId)
        } else {
            selectedIds.insert(assetId)
        }
    }
    
    func selectAll() {
        selectedIds = Set(items.map(\.id))
    }
    
    func deselectAll() {
        selectedIds.removeAll()
    }
    
    func selectSevereOnly() {
        selectedIds = Set(items.filter { $0.isSevere }.map(\.id))
    }
    
    func selectAllInCurrentFilter() {
        for item in filteredItems {
            selectedIds.insert(item.id)
        }
    }
    
    func deselectCurrentFilter() {
        for item in filteredItems {
            selectedIds.remove(item.id)
        }
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
