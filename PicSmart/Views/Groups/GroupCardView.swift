//
//  GroupCardView.swift
//  PicSmart
//

import SwiftUI
import Photos

struct GroupCardView: View {
    let group: AssetGroup
    var isSelectionMode: Bool = false
    var onKeeperChanged: ((String) -> Void)?
    var onToggleMarked: ((String) -> Void)?
    var onDeleteGroup: (() -> Void)?
    var onDeleteSingleAsset: ((String) -> Void)?
    var onCompare: (() -> Void)?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Group Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(group.assets.count) items")
                        .font(.subheadline.weight(.semibold))
                    
                    if group.savingsBytes > 0 {
                        Text("Save ~\(ByteCountFormatter.string(fromByteCount: group.savingsBytes, countStyle: .file)) (\(group.markedForDeletionIds.count) redundant)")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        Text("All items kept")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                Button {
                    onCompare?()
                } label: {
                    Label("Compare", systemImage: "arrow.left.arrow.right")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                if !isSelectionMode {
                    Button {
                        onDeleteGroup?()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                            Text("Keep Best")
                                .fontWeight(.semibold)
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(.blue)
                    .disabled(group.markedForDeletionIds.isEmpty)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            
            // Thumbnails strip
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(group.assets) { asset in
                        let isKeeper = asset.localIdentifier == group.keeperId
                        let isBest = asset.localIdentifier == group.bestShotId
                        let isMarked = group.markedForDeletionIds.contains(asset.localIdentifier)
                        
                        ThumbnailView(
                            asset: asset,
                            badgeText: group.fileSizes[asset.localIdentifier].map {
                                ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
                            },
                            isKeeper: isKeeper,
                            isBestShot: isBest,
                            isSelectionMode: isSelectionMode,
                            isSelected: isMarked,
                            onToggleSelect: {
                                onToggleMarked?(asset.localIdentifier)
                            }
                        )
                        .frame(width: 90, height: 90)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if isSelectionMode {
                                onToggleMarked?(asset.localIdentifier)
                            } else {
                                onCompare?()
                            }
                        }
                        .contextMenu {
                            if !isKeeper {
                                Button {
                                    onKeeperChanged?(asset.localIdentifier)
                                } label: {
                                    Label("Make Keeper", systemImage: "star.fill")
                                }
                            }
                            
                            Button {
                                onToggleMarked?(asset.localIdentifier)
                            } label: {
                                if isMarked {
                                    Label("Keep Photo", systemImage: "checkmark.circle")
                                } else {
                                    Label("Mark for Deletion", systemImage: "trash")
                                }
                            }
                            
                            Divider()
                            
                            Button(role: .destructive) {
                                onDeleteSingleAsset?(asset.localIdentifier)
                            } label: {
                                Label("Delete This Photo Now", systemImage: "trash.fill")
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
