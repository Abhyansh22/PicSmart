//
//  LargeVideosView.swift
//  PicSmart
//

import SwiftUI
import Photos

struct LargeVideosView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppModel.self) private var appModel
    @State private var selectedAsset: PHAsset?
    @State private var isSelectionMode = false
    @State private var selectedIds = Set<String>()
    @State private var showingDeleteAlert = false
    @State private var isCleaning = false
    
    private var viewModel: MediaCollectionViewModel {
        appModel.largeVideosViewModel
    }
    
    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]
    
    private var selectedBytes: Int64 {
        selectedIds.reduce(0) { $0 + (viewModel.fileSizes[$1] ?? 0) }
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()
            
            if viewModel.sortedLargeVideoAssets.isEmpty && !viewModel.hasLoaded {
                ScanningProgressView(
                    category: .largeVideos,
                    progress: viewModel.progress,
                    statusMessage: viewModel.progressMessage ?? "Scanning large videos…",
                    onCancel: {
                        viewModel.cancel()
                    }
                )
            } else if viewModel.sortedLargeVideoAssets.isEmpty {
                ContentUnavailableView(
                    "No Large Videos Found",
                    systemImage: GalleryCategory.largeVideos.iconName,
                    description: Text("No videos exceeding \(AppSettings.formatMB(settings.largeVideoThresholdMB)) found. You can adjust this in Settings.")
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        // Summary Bar
                        HStack {
                            Text("\(viewModel.sortedLargeVideoAssets.count) items")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            
                            Text("(≥ \(AppSettings.formatMB(settings.largeVideoThresholdMB)))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            Spacer()
                            
                            let totalBytes = viewModel.sortedLargeVideoAssets.reduce(0) { $0 + (viewModel.fileSizes[$1.localIdentifier] ?? 0) }
                            if totalBytes > 0 {
                                Text("Total: \(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file))")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(Array(viewModel.sortedLargeVideoAssets.enumerated()), id: \.element.localIdentifier) { index, asset in
                                let sizeText = viewModel.fileSizes[asset.localIdentifier].map {
                                    ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
                                }
                                let isSelected = selectedIds.contains(asset.localIdentifier)
                                
                                ThumbnailView(
                                    asset: asset,
                                    badgeText: sizeText,
                                    isSelectionMode: isSelectionMode,
                                    isSelected: isSelected,
                                    onToggleSelect: {
                                        toggleSelection(asset.localIdentifier)
                                    }
                                )
                                .onTapGesture {
                                    if isSelectionMode {
                                        toggleSelection(asset.localIdentifier)
                                    } else {
                                        selectedAsset = asset
                                    }
                                }
                                .onAppear {
                                    viewModel.prefetch(around: index)
                                }
                            }
                        }
                        .padding(.bottom, isSelectionMode && !selectedIds.isEmpty ? 90 : 20)
                    }
                }
            }
            
            // Bottom Clean Bar in Selection Mode
            if isSelectionMode && !selectedIds.isEmpty {
                bottomCleanBar
            }
        }
        .navigationTitle("Large Videos")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !viewModel.sortedLargeVideoAssets.isEmpty {
                    Button(isSelectionMode ? "Done" : "Select") {
                        withAnimation(.snappy(duration: 0.25)) {
                            isSelectionMode.toggle()
                            if !isSelectionMode {
                                selectedIds.removeAll()
                            }
                        }
                    }
                    .fontWeight(isSelectionMode ? .semibold : .regular)
                }
            }
        }
        .onAppear {
            AnalysisPipelineCoordinator.shared.elevatePriority(for: .largeVideos, in: appModel)
            viewModel.onAppear()
            viewModel.startLoadIfNeeded()
        }
        .onDisappear {
            AnalysisPipelineCoordinator.shared.releasePriority(for: .largeVideos)
            viewModel.onDisappear()
        }
        .task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            viewModel.startLoadIfNeeded()
        }
        .sheet(item: $selectedAsset) { asset in
            FullScreenAssetView(asset: asset)
        }
        .alert("Delete \(selectedIds.count) Large Videos?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete \(selectedIds.count) Videos", role: .destructive) {
                Task {
                    isCleaning = true
                    let toDelete = Array(selectedIds)
                    try? await appModel.deleteAssets(localIdentifiers: toDelete, categoryTitle: "Large Videos")
                    selectedIds.removeAll()
                    isCleaning = false
                    if viewModel.sortedLargeVideoAssets.isEmpty {
                        isSelectionMode = false
                    }
                }
            }
        } message: {
            Text("These \(selectedIds.count) videos will be moved to Recently Deleted in Apple Photos, recovering ~\(ByteCountFormatter.string(fromByteCount: selectedBytes, countStyle: .file)).")
        }
    }
    
    private func toggleSelection(_ id: String) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
    }
    
    private var bottomCleanBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(selectedIds.count) videos selected")
                        .font(.subheadline.weight(.semibold))
                    if selectedBytes > 0 {
                        Text("Free up ~\(ByteCountFormatter.string(fromByteCount: selectedBytes, countStyle: .file))")
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
                        Text("Delete Selected")
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
