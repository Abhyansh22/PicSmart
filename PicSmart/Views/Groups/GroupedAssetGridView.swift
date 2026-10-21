//
//  GroupedAssetGridView.swift
//  PicSmart
//

import SwiftUI
import Photos

struct GroupedAssetGridView: View {
    let category: GalleryCategory
    @State private var viewModel: GroupedScanViewModel
    @State private var showingDeleteConfirmation = false
    @State private var isCleaning = false
    
    init(category: GalleryCategory) {
        self.category = category
        _viewModel = State(wrappedValue: GroupedScanViewModel(category: category))
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()
            
            if viewModel.isScanning && viewModel.groups.isEmpty {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    
                    if let msg = viewModel.statusMessage {
                        Text(msg)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    if let prog = viewModel.progress, prog.total > 0 {
                        ProgressView(value: prog.fractionCompleted)
                            .progressViewStyle(.linear)
                            .padding(.horizontal, 40)
                    }
                }
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
                            ForEach($viewModel.groups) { $group in
                                GroupCardView(
                                    group: $group,
                                    onKeeperChanged: { newKeeper in
                                        viewModel.setKeeper(assetId: newKeeper, in: group.id)
                                    },
                                    onDeleteGroup: {
                                        Task {
                                            try? await viewModel.deleteNonKeepers(in: group)
                                        }
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 90) // space for bottom clean bar
                    }
                }
                .refreshable {
                    viewModel.startScan()
                }
            }
            
            // Bottom Clean Bar
            if !viewModel.groups.isEmpty && viewModel.totalRedundantCount > 0 {
                bottomCleanBar
            }
        }
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if viewModel.groups.isEmpty {
                viewModel.startScan()
            }
        }
        .onDisappear {
            viewModel.cancel()
        }
        .alert("Clean All \(category.title)?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete \(viewModel.totalRedundantCount) Items", role: .destructive) {
                Task {
                    isCleaning = true
                    try? await viewModel.deleteAllNonKeepers()
                    isCleaning = false
                }
            }
        } message: {
            Text("This will keep your chosen keeper for each group and move the remaining \(viewModel.totalRedundantCount) duplicate items to Recently Deleted.")
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
                    Text("\(viewModel.totalRedundantCount) items selected")
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
                            Image(systemName: "trash.fill")
                        }
                        Text("Clean All")
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
