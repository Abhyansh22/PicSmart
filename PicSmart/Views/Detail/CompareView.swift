//
//  CompareView.swift
//  PicSmart
//

import SwiftUI
import Photos
import TipKit

struct CompareView: View {
    @Binding var group: AssetGroup
    var onKeeperChanged: ((String) -> Void)?
    var onToggleMarked: ((String) -> Void)?
    var onDeleteSingleAsset: ((String) -> Void)?
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedIndex: Int = 0
    @State private var showingSingleDeleteConfirmation = false
    
    private var currentAsset: PHAsset? {
        guard group.assets.indices.contains(selectedIndex) else { return nil }
        return group.assets[selectedIndex]
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Context Tip
                TipView(BestShotTip())
                    .padding(.horizontal)
                    .padding(.top, 4)
                
                // Main photo preview
                TabView(selection: $selectedIndex) {
                    ForEach(Array(group.assets.enumerated()), id: \.element.localIdentifier) { index, asset in
                        VStack(spacing: 12) {
                            ZStack(alignment: .topTrailing) {
                                HighResolutionAssetImage(asset: asset, allowZoom: true)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                
                                HStack(spacing: 8) {
                                    if asset.localIdentifier == group.bestShotId {
                                        Label("Best Shot", systemImage: "sparkles")
                                            .font(.caption.weight(.semibold))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(.ultraThinMaterial, in: Capsule())
                                            .foregroundStyle(.yellow)
                                    }
                                    if asset.localIdentifier == group.keeperId {
                                        Label("Keeper", systemImage: "star.fill")
                                            .font(.caption.weight(.semibold))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(Color.blue, in: Capsule())
                                            .foregroundStyle(.white)
                                    } else if group.markedForDeletionIds.contains(asset.localIdentifier) {
                                        Label("Marked for Trash", systemImage: "trash.fill")
                                            .font(.caption.weight(.semibold))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(Color.red, in: Capsule())
                                            .foregroundStyle(.white)
                                    } else {
                                        Label("Kept", systemImage: "checkmark.circle")
                                            .font(.caption.weight(.semibold))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(.ultraThinMaterial, in: Capsule())
                                            .foregroundStyle(.primary)
                                    }
                                }
                                .padding(16)
                            }
                            .padding(.horizontal)
                            
                            HStack(spacing: 16) {
                                Label(asset.formattedDimensions, systemImage: "aspectratio")
                                if let size = group.fileSizes[asset.localIdentifier] {
                                    Label(ByteCountFormatter.string(fromByteCount: size, countStyle: .file), systemImage: "internaldrive")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 4)
                        }
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))
                
                // Granular Per-Photo Action Bar
                if let asset = currentAsset {
                    let isKeeper = asset.localIdentifier == group.keeperId
                    let isMarked = group.markedForDeletionIds.contains(asset.localIdentifier)
                    
                    HStack(spacing: 12) {
                        Button {
                            onToggleMarked?(asset.localIdentifier)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: isMarked ? "arrow.uturn.backward.circle" : "trash")
                                Text(isMarked ? "Keep This Photo" : "Mark for Deletion")
                                    .fontWeight(.medium)
                            }
                            .font(.subheadline)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(isMarked ? Color.green.opacity(0.15) : Color.orange.opacity(0.15), in: Capsule())
                            .foregroundStyle(isMarked ? Color.green : Color.orange)
                        }
                        
                        if !isKeeper {
                            Button {
                                group.keeperId = asset.localIdentifier
                                onKeeperChanged?(asset.localIdentifier)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "star.fill")
                                    Text("Make Keeper")
                                        .fontWeight(.medium)
                                }
                                .font(.subheadline)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.blue.opacity(0.15), in: Capsule())
                                .foregroundStyle(Color.blue)
                            }
                        }
                        
                        Spacer()
                        
                        Button(role: .destructive) {
                            showingSingleDeleteConfirmation = true
                        } label: {
                            Image(systemName: "trash.fill")
                                .font(.subheadline)
                                .padding(8)
                                .background(Color.red.opacity(0.15), in: Circle())
                                .foregroundStyle(Color.red)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color(uiColor: .tertiarySystemBackground))
                }
                
                // Bottom filmstrip to switch keeper
                VStack(spacing: 8) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Array(group.assets.enumerated()), id: \.element.localIdentifier) { index, asset in
                                let isKeeper = asset.localIdentifier == group.keeperId
                                let isMarked = group.markedForDeletionIds.contains(asset.localIdentifier)
                                
                                Button {
                                    selectedIndex = index
                                } label: {
                                    ZStack(alignment: .topTrailing) {
                                        ThumbnailView(
                                            asset: asset,
                                            isKeeper: isKeeper,
                                            isBestShot: asset.localIdentifier == group.bestShotId
                                        )
                                        .frame(width: 64, height: 64)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(
                                                    selectedIndex == index ? Color.primary : (isKeeper ? Color.blue : (isMarked ? Color.red : Color.clear)),
                                                    lineWidth: selectedIndex == index ? 3 : 2
                                                )
                                        )
                                        
                                        if isMarked {
                                            Image(systemName: "trash.circle.fill")
                                                .font(.system(size: 14))
                                                .foregroundStyle(.white, Color.red)
                                                .padding(2)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical, 12)
                .background(Color(uiColor: .secondarySystemBackground))
            }
            .navigationTitle("Inspect & Select")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .alert("Delete This Photo?", isPresented: $showingSingleDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    if let asset = currentAsset {
                        let id = asset.localIdentifier
                        onDeleteSingleAsset?(id)
                        if group.assets.count <= 2 {
                            dismiss()
                        } else {
                            selectedIndex = max(0, selectedIndex - 1)
                        }
                    }
                }
            } message: {
                Text("This individual photo will be moved to Apple Photos Recently Deleted album.")
            }
        }
    }
}
