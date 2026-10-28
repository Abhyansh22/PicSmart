//
//  GroupedAssetGridView.swift
//  PicSmart
//

import SwiftUI
import Photos

struct GroupedAssetGridView: View {
    let category: GalleryCategory
    @Environment(AppModel.self) private var appModel
    @State private var showingDeleteConfirmation = false
    @State private var isCleaning = false
    @State private var isSelectionMode = false
    
    private var viewModel: GroupedScanViewModel {
        appModel.groupedViewModel(for: category)
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()
            
            if viewModel.groups.isEmpty && !viewModel.hasCompletedScan {
                ScanningProgressView(
                    category: category,
                    progress: viewModel.progress,
                    statusMessage: viewModel.statusMessage ?? "Preparing analysis…"
                )
            } else if viewModel.groups.isEmpty {
                ContentUnavailableView(
                    "No \(category.title) Found",
                    systemImage: category.iconName,
                    description: Text("No items matching this criteria were detected in your gallery.")
                )
            } else {
                ScrollView {
                    VStack(spacing: 14) {
                        // Summary Card
                        summaryCard
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                        
                        // In-progress banner if background scan is still refining
                        if viewModel.isScanning, let msg = viewModel.statusMessage {
                            HStack(spacing: 10) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text(msg)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16)
                        }
                        
                        // Groups List
                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.groups) { group in
                                GroupCardView(
                                    group: Binding(
                                        get: {
                                            if let idx = viewModel.groups.firstIndex(where: { $0.id == group.id }) {
                                                return viewModel.groups[idx]
                                            }
                                            return group
                                        },
                                        set: { newGroup in
                                            if let idx = viewModel.groups.firstIndex(where: { $0.id == group.id }) {
                                                viewModel.groups[idx] = newGroup
                                            }
                                        }
                                    ),
                                    isSelectionMode: isSelectionMode,
                                    onKeeperChanged: { newKeeper in
                                        viewModel.setKeeper(assetId: newKeeper, in: group.id)
                                    },
                                    onToggleMarked: { assetId in
                                        viewModel.toggleMarkedForDeletion(assetId: assetId, in: group.id)
                                    },
                                    onDeleteGroup: {
                                        Task {
                                            let toDelete = Array(group.markedForDeletionIds)
                                            guard !toDelete.isEmpty else { return }
                                            try? await appModel.deleteAssets(localIdentifiers: toDelete, categoryTitle: category.title)
                                        }
                                    },
                                    onDeleteSingleAsset: { assetId in
                                        Task {
                                            try? await appModel.deleteAssets(localIdentifiers: [assetId], categoryTitle: category.title)
                                        }
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 90) // space for bottom clean bar
                    }
                }
            }
            
            // Bottom Clean Bar
            if !viewModel.groups.isEmpty && viewModel.totalRedundantCount > 0 {
                bottomCleanBar
            }
        }
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !viewModel.groups.isEmpty {
                    Button(isSelectionMode ? "Done" : "Select") {
                        withAnimation(.snappy(duration: 0.25)) {
                            isSelectionMode.toggle()
                        }
                    }
                    .fontWeight(isSelectionMode ? .semibold : .regular)
                }
            }
        }
        .onAppear {
            AnalysisPipelineCoordinator.shared.elevatePriority(for: category, in: appModel)
            viewModel.onAppear()
            viewModel.startScanIfNeeded()
        }
        .onDisappear {
            AnalysisPipelineCoordinator.shared.releasePriority(for: category)
            viewModel.onDisappear()
        }
        .task {
            // Defer scan start by 350ms to allow UINavigationController push transition to settle cleanly
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            viewModel.startScanIfNeeded()
        }
        .alert("Clean All Marked \(category.title)?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete \(viewModel.totalRedundantCount) Items", role: .destructive) {
                Task {
                    isCleaning = true
                    let allMarked = viewModel.groups.flatMap { Array($0.markedForDeletionIds) }
                    try? await appModel.deleteAssets(localIdentifiers: allMarked, categoryTitle: category.title)
                    isCleaning = false
                }
            }
        } message: {
            Text("This will move the \(viewModel.totalRedundantCount) marked photos to Recently Deleted while keeping all unmarked and keeper photos safe.")
        }
    }
    
    // MARK: - Summary Card
    private var summaryCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(viewModel.groups.count) groups · \(viewModel.totalRedundantCount) extra copies")
                    .font(.subheadline.weight(.semibold))
                
                if viewModel.totalSavingsBytes > 0 {
                    Text("Can recover ~\(ByteCountFormatter.string(fromByteCount: viewModel.totalSavingsBytes, countStyle: .file))")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            Spacer()
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
    
    // MARK: - Floating Clean Bar
    private var bottomCleanBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isSelectionMode ? "\(viewModel.totalRedundantCount) items selected" : "\(viewModel.totalRedundantCount) redundant items")
                        .font(.subheadline.weight(.semibold))
                    if viewModel.totalSavingsBytes > 0 {
                        Text("Free up ~\(ByteCountFormatter.string(fromByteCount: viewModel.totalSavingsBytes, countStyle: .file))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                Button {
                    showingDeleteConfirmation = true
                } label: {
                    HStack(spacing: 6) {
                        if isCleaning {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: isSelectionMode ? "trash.fill" : "sparkles")
                        }
                        Text(isSelectionMode ? "Delete Marked" : "Clean Redundant")
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
