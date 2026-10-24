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
    @State private var selectedAssetForPreview = false
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
                    VStack(spacing: 10) {
                        // Summary & Controls Header (Quick filters shown only in selection mode)
                        summaryCard
                            .padding(.horizontal, 16)
                            .padding(.top, 10)
                        
                        // Media Grid
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(viewModel.items) { item in
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
                                        Image(systemName: "camera.metering.spot")
                                            .font(.system(size: 8))
                                        Text("\(item.blurPercentage)%")
                                            .font(.system(size: 10, weight: .bold))
                                    }
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(.ultraThinMaterial, in: Capsule())
                                    .foregroundStyle(item.blurPercentage >= 75 ? Color.orange : Color.secondary)
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
                        .padding(.bottom, isSelectionMode && viewModel.selectedCount > 0 ? 90 : 20)
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
                                viewModel.selectHighlyBlurredOnly()
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
    
    // MARK: - Summary & Quick Filters
    
    private var summaryCard: some View {
        VStack(spacing: 8) {
            HStack {
                Text("\(viewModel.items.count) photos with low sharpness")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                if isSelectionMode && viewModel.selectedSavingsBytes > 0 {
                    Text("Selected ~\(ByteCountFormatter.string(fromByteCount: viewModel.selectedSavingsBytes, countStyle: .file))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }
            
            if isSelectionMode {
                HStack(spacing: 8) {
                    Button("Highly Blurry (≥ 75%)") {
                        viewModel.selectHighlyBlurredOnly()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(.blue)
                    
                    Button("Select All") {
                        viewModel.selectAll()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    Button("Deselect") {
                        viewModel.deselectAll()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    Spacer()
                }
                .transition(.opacity)
            }
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
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
