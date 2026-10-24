//
//  BlurredPhotosView.swift
//  PicSmart
//

import SwiftUI
import Photos

struct BlurredPhotosView: View {
    @Environment(AppModel.self) private var appModel
    @State private var showingDeleteAlert = false
    @State private var isCleaning = false
    @State private var activeAsset: PHAsset?
    @State private var isSelectionMode = false
    
    private var viewModel: BlurredPhotosViewModel {
        appModel.blurredPhotosViewModel
    }
    
    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]
    
    var body: some View {
        @Bindable var vm = viewModel
        
        ZStack(alignment: .bottom) {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()
            
            if viewModel.items.isEmpty && !viewModel.hasCompletedScan {
                ScanningProgressView(
                    category: .blurredPhotos,
                    progress: viewModel.progress,
                    statusMessage: viewModel.statusMessage ?? "Analyzing sharpness…",
                    onCancel: { viewModel.cancel() }
                )
            } else if viewModel.items.isEmpty {
                ContentUnavailableView(
                    "No Blurred Photos",
                    systemImage: "sparkles",
                    description: Text("All photos in your library have high sharpness and clarity.")
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        // Native Segmented Filter Tabs
                        Picker("Blur Filter", selection: $vm.selectedTab) {
                            ForEach(BlurFilterTab.allCases) { tab in
                                Text(tabTitle(for: tab)).tag(tab)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        
                        // Summary & Selection Actions Header
                        filterHeader
                            .padding(.horizontal, 16)
                        
                        // Empty state for specific filter if no items match
                        if viewModel.filteredItems.isEmpty {
                            ContentUnavailableView(
                                "No \(viewModel.selectedTab.rawValue) Photos",
                                systemImage: "checkmark.circle",
                                description: Text("No photos match this blur level.")
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                        } else {
                            // Media Grid
                            LazyVGrid(columns: columns, spacing: 2) {
                                ForEach(viewModel.filteredItems) { item in
                                    let isSelected = viewModel.selectedIds.contains(item.id)
                                    
                                    ZStack(alignment: .bottomLeading) {
                                        ThumbnailView(
                                            asset: item.asset,
                                            isSelectionMode: isSelectionMode,
                                            isSelected: isSelected,
                                            onToggleSelect: {
                                                viewModel.toggleSelection(item.id)
                                            }
                                        )
                                        .aspectRatio(1, contentMode: .fill)
                                        .clipped()
                                        
                                        // Subtle Blur Score Badge
                                        HStack(spacing: 3) {
                                            Image(systemName: item.isSevere ? "camera.metering.spot" : "aqi.medium")
                                                .font(.system(size: 8))
                                            Text("\(item.blurPercentage)%")
                                                .font(.system(size: 10, weight: .bold))
                                        }
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(.ultraThinMaterial, in: Capsule())
                                        .foregroundStyle(item.isSevere ? Color.orange : Color.secondary)
                                        .padding(6)
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        if isSelectionMode {
                                            viewModel.toggleSelection(item.id)
                                        } else {
                                            activeAsset = item.asset
                                        }
                                    }
                                    .contextMenu {
                                        Button {
                                            viewModel.toggleSelection(item.id)
                                        } label: {
                                            Label(isSelected ? "Deselect" : "Select for Deletion", systemImage: isSelected ? "circle" : "checkmark.circle")
                                        }
                                        
                                        Button(role: .destructive) {
                                            Task {
                                                try? await appModel.deleteAssets(localIdentifiers: [item.id], categoryTitle: "Blurred Photos")
                                            }
                                        } label: {
                                            Label("Delete This Photo", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                            .padding(.bottom, isSelectionMode && viewModel.selectedCount > 0 ? 90 : 24)
                        }
                    }
                }
            }
            
            // Bottom Clean Bar in Selection Mode
            if isSelectionMode && viewModel.selectedCount > 0 {
                bottomCleanBar
            }
        }
        .navigationTitle("Blurred Photos")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !viewModel.items.isEmpty {
                    Button(isSelectionMode ? "Done" : "Select") {
                        withAnimation(.snappy(duration: 0.25)) {
                            isSelectionMode.toggle()
                            if !isSelectionMode {
                                viewModel.deselectAll()
                            } else {
                                if viewModel.selectedTab == .severe {
                                    viewModel.selectAllInCurrentFilter()
                                } else {
                                    viewModel.selectSevereOnly()
                                }
                            }
                        }
                    }
                    .fontWeight(isSelectionMode ? .semibold : .regular)
                }
            }
        }
        .onAppear {
            AnalysisPipelineCoordinator.shared.elevatePriority(for: .blurredPhotos, in: appModel)
            viewModel.onAppear()
            viewModel.startScanIfNeeded()
        }
        .onDisappear {
            AnalysisPipelineCoordinator.shared.releasePriority(for: .blurredPhotos)
            viewModel.onDisappear()
        }
        .sheet(item: $activeAsset) { asset in
            FullScreenAssetView(asset: asset)
        }
        .alert("Delete \(viewModel.selectedCount) Blurred Photos?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete \(viewModel.selectedCount) Photos", role: .destructive) {
                Task {
                    isCleaning = true
                    let toDelete = Array(viewModel.selectedIds)
                    try? await appModel.deleteAssets(localIdentifiers: toDelete, categoryTitle: "Blurred Photos")
                    isCleaning = false
                    if viewModel.items.isEmpty {
                        isSelectionMode = false
                    }
                }
            }
        } message: {
            Text("These \(viewModel.selectedCount) photos will be moved to Recently Deleted in Apple Photos.")
        }
    }
    
    // MARK: - Filter Header & Controls
    
    private func tabTitle(for tab: BlurFilterTab) -> String {
        switch tab {
        case .all:
            return "All (\(viewModel.items.count))"
        case .severe:
            return "Severe (\(viewModel.severeCount))"
        case .soft:
            return "Soft Focus (\(viewModel.softCount))"
        }
    }
    
    private var isAllInCurrentFilterSelected: Bool {
        let current = viewModel.filteredItems
        guard !current.isEmpty else { return false }
        return current.allSatisfy { viewModel.selectedIds.contains($0.id) }
    }
    
    private var filterHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(filterSummaryText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                
                if isSelectionMode && viewModel.selectedSavingsBytes > 0 {
                    Text("Selected ~\(ByteCountFormatter.string(fromByteCount: viewModel.selectedSavingsBytes, countStyle: .file))")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else if viewModel.totalPotentialSavingsBytes > 0 {
                    Text("Can recover ~\(ByteCountFormatter.string(fromByteCount: viewModel.totalPotentialSavingsBytes, countStyle: .file))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            if isSelectionMode && !viewModel.filteredItems.isEmpty {
                Button(isAllInCurrentFilterSelected ? "Deselect All" : "Select All") {
                    withAnimation(.snappy) {
                        if isAllInCurrentFilterSelected {
                            viewModel.deselectCurrentFilter()
                        } else {
                            viewModel.selectAllInCurrentFilter()
                        }
                    }
                }
                .font(.subheadline.weight(.medium))
            }
        }
        .padding(.vertical, 4)
    }
    
    private var filterSummaryText: String {
        switch viewModel.selectedTab {
        case .all:
            return "\(viewModel.items.count) photos with focus issues"
        case .severe:
            return "\(viewModel.severeCount) severely blurred photos"
        case .soft:
            return "\(viewModel.softCount) soft focus photos"
        }
    }
    
    // MARK: - Floating Clean Bar
    
    private var bottomCleanBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(viewModel.selectedCount) items selected")
                        .font(.subheadline.weight(.semibold))
                    if viewModel.selectedSavingsBytes > 0 {
                        Text("Free up ~\(ByteCountFormatter.string(fromByteCount: viewModel.selectedSavingsBytes, countStyle: .file))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                Button {
                    showingDeleteAlert = true
                } label: {
                    HStack(spacing: 6) {
                        if isCleaning {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "trash.fill")
                        }
                        Text("Clean Selected")
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.red, in: Capsule())
                    .foregroundStyle(.white)
                }
                .disabled(isCleaning)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
        }
    }
}
