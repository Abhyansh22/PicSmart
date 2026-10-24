//
//  PeopleCleanupReviewView.swift
//  PicSmart
//

import SwiftUI
import Photos

enum PeopleCleanupType: String, Identifiable {
    case blinks = "Blinks & Closed Eyes"
    case unfocused = "Unfocused Portraits"
    
    var id: String { rawValue }
    
    var iconName: String {
        switch self {
        case .blinks: return "eye.slash.fill"
        case .unfocused: return "camera.metering.spot"
        }
    }
    
    var description: String {
        switch self {
        case .blinks:
            return "Photos where one or more people have closed eyes or blinked."
        case .unfocused:
            return "Portrait shots with motion blur or soft focus."
        }
    }
}

struct PeopleCleanupReviewView: View {
    let cleanupType: PeopleCleanupType
    let items: [PersonPhotoItem]
    
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedIds = Set<String>()
    @State private var activeAsset: PHAsset?
    @State private var showingDeleteAlert = false
    @State private var isCleaning = false
    
    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]
    
    private var selectedBytes: Int64 {
        items.filter { selectedIds.contains($0.id) }
            .reduce(0) { $0 + $1.fileSize }
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()
            
            if items.isEmpty {
                ContentUnavailableView(
                    "No Issues Found",
                    systemImage: "checkmark.circle.fill",
                    description: Text("No \(cleanupType.rawValue.lowercased()) detected in your gallery.")
                )
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        // Header Guidance Card
                        HStack(spacing: 12) {
                            Image(systemName: cleanupType.iconName)
                                .font(.title2)
                                .foregroundStyle(.blue)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(cleanupType.rawValue)
                                    .font(.subheadline.weight(.semibold))
                                Text(cleanupType.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(14)
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        
                        // Select All / Deselect Toolbar
                        HStack(spacing: 8) {
                            Button("Select All (\(items.count))") {
                                selectedIds = Set(items.map(\.id))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            
                            Button("Deselect") {
                                selectedIds.removeAll()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        
                        // Photos Grid
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(items) { item in
                                let isSelected = selectedIds.contains(item.id)
                                
                                ThumbnailView(
                                    asset: item.asset,
                                    badgeText: ByteCountFormatter.string(fromByteCount: item.fileSize, countStyle: .file),
                                    isSelectionMode: true,
                                    isSelected: isSelected,
                                    onToggleSelect: {
                                        toggleSelection(item.id)
                                    }
                                )
                                .onTapGesture {
                                    activeAsset = item.asset
                                }
                            }
                        }
                        .padding(.bottom, !selectedIds.isEmpty ? 90 : 20)
                    }
                }
            }
            
            // Bottom Clean Bar
            if !selectedIds.isEmpty {
                bottomCleanBar
            }
        }
        .navigationTitle(cleanupType.rawValue)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $activeAsset) { asset in
            FullScreenAssetView(asset: asset)
        }
        .onAppear {
            // Pre-select all items by default for one-tap convenience
            selectedIds = Set(items.map(\.id))
        }
        .alert("Delete \(selectedIds.count) Photos?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete \(selectedIds.count) Photos", role: .destructive) {
                Task {
                    isCleaning = true
                    let toDelete = Array(selectedIds)
                    try? await appModel.deleteAssets(localIdentifiers: toDelete, categoryTitle: cleanupType.rawValue)
                    selectedIds.removeAll()
                    isCleaning = false
                    dismiss()
                }
            }
        } message: {
            Text("These \(selectedIds.count) photos will be moved to Recently Deleted in Apple Photos.")
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
                    Text("\(selectedIds.count) photos selected")
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
