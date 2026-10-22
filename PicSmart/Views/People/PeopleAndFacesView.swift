//
//  PeopleAndFacesView.swift
//  PicSmart
//

import SwiftUI
import Photos

struct PeopleAndFacesView: View {
    @Environment(AppModel.self) private var appModel
    @State private var showingDeleteAlert = false
    @State private var isCleaning = false
    @State private var selectedAssetForPreview: PHAsset?
    
    private var viewModel: PeopleAndFacesViewModel {
        appModel.peopleAndFacesViewModel
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
                    category: .people,
                    progress: viewModel.progress,
                    statusMessage: viewModel.statusMessage ?? "Clustering people & faces…",
                    onCancel: { viewModel.cancel() }
                )
            } else if viewModel.items.isEmpty && viewModel.personClusters.isEmpty {
                ContentUnavailableView(
                    "No People Found",
                    systemImage: "person.2.slash",
                    description: Text("No photos with clear human faces were detected in your gallery.")
                )
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        // Section 1: Google Photos-style People Avatars Carousel
                        if !viewModel.personClusters.isEmpty {
                            peopleAvatarsSection
                                .padding(.top, 12)
                        }
                        
                        Divider()
                            .padding(.horizontal, 16)
                        
                        // Section 2: Filter Pills Bar
                        filterPillsBar
                            .padding(.horizontal, 16)
                        
                        // Section 3: Summary & Controls Header
                        summaryCard
                            .padding(.horizontal, 16)
                        
                        if viewModel.filteredItems.isEmpty {
                            ContentUnavailableView(
                                "No Matching Photos",
                                systemImage: viewModel.selectedFilter.iconName,
                                description: Text("No photos found in \(viewModel.selectedFilter.rawValue).")
                            )
                            .padding(.top, 30)
                        } else {
                            // Media Grid
                            LazyVGrid(columns: columns, spacing: 6) {
                                ForEach(viewModel.filteredItems) { item in
                                    let isSelected = viewModel.selectedIds.contains(item.id)
                                    
                                    ZStack(alignment: .topTrailing) {
                                        ZStack(alignment: .bottomLeading) {
                                            ThumbnailView(
                                                asset: item.asset,
                                                badgeText: ByteCountFormatter.string(fromByteCount: item.fileSize, countStyle: .file)
                                            )
                                            .aspectRatio(1, contentMode: .fill)
                                            .clipped()
                                            
                                            // Face Info Tag
                                            HStack(spacing: 4) {
                                                if item.hasBlinkedEyes {
                                                    Image(systemName: "eye.slash.fill")
                                                        .font(.system(size: 9))
                                                    Text("Blink")
                                                        .font(.system(size: 10, weight: .bold))
                                                } else if item.isSoloPortrait {
                                                    Text("1 Person")
                                                        .font(.system(size: 10, weight: .bold))
                                                } else {
                                                    Text("\(item.faceCount) People")
                                                        .font(.system(size: 10, weight: .bold))
                                                }
                                            }
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(.ultraThinMaterial, in: Capsule())
                                            .foregroundStyle(item.hasBlinkedEyes ? Color.red : Color.cyan)
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
                                                try? await appModel.deleteAssets(localIdentifiers: [item.id], categoryTitle: "People & Faces")
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
        .navigationTitle("People & Faces")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            AnalysisPipelineCoordinator.shared.elevatePriority(for: .people, in: appModel)
            viewModel.onAppear()
            viewModel.startScanIfNeeded()
        }
        .onDisappear {
            AnalysisPipelineCoordinator.shared.releasePriority(for: .people)
            viewModel.onDisappear()
        }
        .sheet(item: $selectedAssetForPreview) { asset in
            FullScreenAssetView(asset: asset)
        }
        .alert("Delete \(viewModel.selectedCount) Selected Photos?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete \(viewModel.selectedCount) Photos", role: .destructive) {
                Task {
                    isCleaning = true
                    let toDelete = Array(viewModel.selectedIds)
                    try? await appModel.deleteAssets(localIdentifiers: toDelete, categoryTitle: "People & Faces")
                    isCleaning = false
                }
            }
        } message: {
            Text("These \(viewModel.selectedCount) photos will be moved to Recently Deleted in Apple Photos.")
        }
    }
    
    // MARK: - Section 1: Google Photos People Carousel
    
    private var peopleAvatarsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("People & Groups")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                
                Text("\(viewModel.personClusters.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Spacer()
            }
            .padding(.horizontal, 16)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(Array(viewModel.personClusters.indices), id: \.self) { idx in
                        let cluster = viewModel.personClusters[idx]
                        
                        NavigationLink {
                            PersonDetailView(
                                person: Binding(
                                    get: { viewModel.personClusters[idx] },
                                    set: { viewModel.personClusters[idx] = $0 }
                                ),
                                onRename: { newName in
                                    viewModel.renamePerson(id: cluster.id, newName: newName)
                                }
                            )
                        } label: {
                            VStack(spacing: 8) {
                                FaceAvatarView(
                                    asset: cluster.avatarAsset,
                                    faceBoundingBox: cluster.avatarFaceBoundingBox,
                                    size: 76
                                )
                                
                                VStack(spacing: 2) {
                                    Text(cluster.displayName)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                        .frame(maxWidth: 85)
                                    
                                    Text("\(cluster.count) photo\(cluster.count == 1 ? "" : "s")")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
    
    // MARK: - Section 2: Filter Pills Bar
    
    private var filterPillsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(PeopleFilter.allCases) { filter in
                    let isSelected = viewModel.selectedFilter == filter
                    Button {
                        withAnimation(.snappy) {
                            viewModel.selectedFilter = filter
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: filter.iconName)
                            Text(filter.rawValue)
                                .fontWeight(isSelected ? .semibold : .regular)
                            
                            if filter == .blinks {
                                let blinkCount = viewModel.items.filter { $0.hasBlinkedEyes }.count
                                if blinkCount > 0 {
                                    Text("\(blinkCount)")
                                        .font(.caption2.weight(.bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.red, in: Capsule())
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                        .font(.footnote)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(isSelected ? Color.blue : Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    // MARK: - Summary Card
    
    private var summaryCard: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(viewModel.filteredItems.count) \(viewModel.selectedFilter.rawValue.lowercased())")
                        .font(.subheadline.weight(.semibold))
                    
                    if viewModel.selectedSavingsBytes > 0 {
                        Text("Selected ~\(ByteCountFormatter.string(fromByteCount: viewModel.selectedSavingsBytes, countStyle: .file))")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
                Spacer()
                
                HStack(spacing: 8) {
                    Button("Select All") {
                        viewModel.selectAllInFilter()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    if viewModel.selectedCount > 0 {
                        Button("Deselect") {
                            viewModel.deselectAll()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
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
