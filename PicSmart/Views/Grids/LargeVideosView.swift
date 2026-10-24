//
//  LargeVideosView.swift
//  PicSmart
//

import SwiftUI
import Photos

struct LargeVideosView: View {
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
                    statusMessage: viewModel.progressMessage ?? "Analyzing videos…",
                    onCancel: {
                        viewModel.cancel()
                    }
                )
            } else if viewModel.sortedLargeVideoAssets.isEmpty {
                ContentUnavailableView(
                    "No Videos Found",
                    systemImage: "video.slash",
                    description: Text("No video files were found in your photo library.")
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18, pinnedViews: [.sectionHeaders]) {
                        // Overall Summary Bar
                        summaryBar
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                        
                        // Descending Size Tier Sections
                        ForEach(viewModel.videoSections) { section in
                            Section {
                                LazyVGrid(columns: columns, spacing: 2) {
                                    ForEach(section.assets, id: \.localIdentifier) { asset in
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
                                    }
                                }
                            } header: {
                                sectionHeader(for: section)
                            }
                        }
                    }
                    .padding(.bottom, isSelectionMode && !selectedIds.isEmpty ? 90 : 24)
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
        .alert("Delete \(selectedIds.count) Videos?", isPresented: $showingDeleteAlert) {
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
    
    // MARK: - Subviews
    
    private var summaryBar: some View {
        HStack {
            Text("\(viewModel.sortedLargeVideoAssets.count) video\(viewModel.sortedLargeVideoAssets.count == 1 ? "" : "s")")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            
            Spacer()
            
            let totalBytes = viewModel.sortedLargeVideoAssets.reduce(0) {
                $0 + (viewModel.fileSizes[$1.localIdentifier] ?? 0)
            }
            if totalBytes > 0 {
                Text("Total: \(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file))")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
            }
        }
    }
    
    private func sectionHeader(for section: VideoSizeSection) -> some View {
        let sectionIds = Set(section.assets.map(\.localIdentifier))
        let isAllSelected = !sectionIds.isEmpty && sectionIds.isSubset(of: selectedIds)
        
        return HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: section.tier.iconName)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                    
                    Text(section.title)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)
                }
                
                Text("\(section.assets.count) video\(section.assets.count == 1 ? "" : "s") • \(ByteCountFormatter.string(fromByteCount: section.totalBytes, countStyle: .file))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if isSelectionMode {
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        if isAllSelected {
                            selectedIds.subtract(sectionIds)
                        } else {
                            selectedIds.formUnion(sectionIds)
                        }
                    }
                } label: {
                    Text(isAllSelected ? "Deselect" : "Select All")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
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
