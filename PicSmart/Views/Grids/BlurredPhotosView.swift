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
    @State private var selectedAssetForPreview: PHAsset?
    
    private var viewModel: BlurredPhotosViewModel {
        appModel.blurredPhotosViewModel
    }
    
    private let columns = [
        GridItem(.adaptive(minimum: 105, maximum: 140), spacing: 6)
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
                    VStack(spacing: 12) {
                        // Summary & Controls Header
                        summaryCard
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                        
                        // Media Grid
                        LazyVGrid(columns: columns, spacing: 6) {
                            ForEach(viewModel.items) { item in
                                let isSelected = viewModel.selectedIds.contains(item.id)
                                
                                ZStack(alignment: .topTrailing) {
                                    ZStack(alignment: .bottomLeading) {
                                        ThumbnailView(
                                            asset: item.asset,
                                            badgeText: ByteCountFormatter.string(fromByteCount: item.fileSize, countStyle: .file)
                                        )
                                        .aspectRatio(1, contentMode: .fill)
                                        .clipped()
                                        
                                        // Blur Score Tag
                                        Text("\(item.blurPercentage)% Blurry")
                                            .font(.system(size: 10, weight: .bold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(.ultraThinMaterial, in: Capsule())
                                            .foregroundStyle(item.blurPercentage >= 75 ? Color.red : Color.orange)
                                            .padding(6)
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedAssetForPreview = item.asset
                                    }
                                    
                                    // Selection Circle Toggle
                                    Button {
                                        viewModel.toggleSelection(item.id)
                                    } label: {
                                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 20, weight: .bold))
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(
                                                isSelected ? .white : .secondary,
                                                isSelected ? Color.blue : Color.black.opacity(0.4)
                                            )
                                            .background(Circle().fill(.ultraThinMaterial))
                                            .padding(6)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                                )
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
                        .padding(.horizontal, 16)
                        .padding(.bottom, 90) // space for bottom clean bar
                    }
                }
                .refreshable {
                    await viewModel.refresh()
                }
            }
            
            // Bottom Clean Bar
            if !viewModel.items.isEmpty && viewModel.selectedCount > 0 {
                bottomCleanBar
            }
        }
        .navigationTitle("Blurred Photos")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            AnalysisPipelineCoordinator.shared.elevatePriority(for: .blurredPhotos, in: appModel)
            viewModel.onAppear()
            viewModel.startScanIfNeeded()
        }
        .onDisappear {
            AnalysisPipelineCoordinator.shared.releasePriority(for: .blurredPhotos)
            viewModel.onDisappear()
        }
        .sheet(item: $selectedAssetForPreview) { asset in
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
                }
            }
        } message: {
            Text("These \(viewModel.selectedCount) photos will be moved to Recently Deleted in Apple Photos.")
        }
    }
    
    // MARK: - Summary & Quick Filters
    
    private var summaryCard: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(viewModel.items.count) photos with low sharpness")
                        .font(.subheadline.weight(.semibold))
                    
                    if viewModel.selectedSavingsBytes > 0 {
                        Text("Selected ~\(ByteCountFormatter.string(fromByteCount: viewModel.selectedSavingsBytes, countStyle: .file))")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
                Spacer()
            }
            
            HStack(spacing: 8) {
                Button("Highly Blurry") {
                    viewModel.selectHighlyBlurredOnly()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button("Select All") {
                    viewModel.selectAll()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button("Deselect All") {
                    viewModel.deselectAll()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Spacer()
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
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
