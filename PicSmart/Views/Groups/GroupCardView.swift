//
//  GroupCardView.swift
//  PicSmart
//

import SwiftUI
import Photos

struct GroupCardView: View {
    @Binding var group: AssetGroup
    var onKeeperChanged: ((String) -> Void)?
    var onToggleMarked: ((String) -> Void)?
    var onDeleteGroup: (() -> Void)?
    var onDeleteSingleAsset: ((String) -> Void)?
    
    @State private var showingCompare = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Group Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(group.assets.count) items")
                        .font(.subheadline.weight(.semibold))
                    
                    if group.savingsBytes > 0 {
                        Text("Save ~\(ByteCountFormatter.string(fromByteCount: group.savingsBytes, countStyle: .file)) (\(group.markedForDeletionIds.count) marked)")
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
                    showingCompare = true
                } label: {
                    Label("Compare", systemImage: "arrow.left.arrow.right")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button(role: .destructive) {
                    onDeleteGroup?()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                        if group.markedForDeletionIds.count > 0 {
                            Text("\(group.markedForDeletionIds.count)")
                                .font(.caption2.weight(.bold))
                        }
                    }
                    .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.red)
                .disabled(group.markedForDeletionIds.isEmpty)
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
                        
                        ZStack(alignment: .topTrailing) {
                            ThumbnailView(
                                asset: asset,
                                badgeText: group.fileSizes[asset.localIdentifier].map {
                                    ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
                                },
                                isKeeper: isKeeper,
                                isBestShot: isBest
                            )
                            .frame(width: 90, height: 90)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(
                                        isKeeper ? Color.blue : (isMarked ? Color.red.opacity(0.8) : Color.clear),
                                        lineWidth: isKeeper ? 2.5 : (isMarked ? 2.0 : 0)
                                    )
                            )
                            
                            // Interactive Selection / Trash Badge
                            Button {
                                onToggleMarked?(asset.localIdentifier)
                            } label: {
                                Image(systemName: isKeeper ? "star.circle.fill" : (isMarked ? "trash.circle.fill" : "circle"))
                                    .font(.system(size: 18, weight: .bold))
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(
                                        isKeeper ? .white : (isMarked ? .white : .secondary),
                                        isKeeper ? Color.blue : (isMarked ? Color.red : Color.black.opacity(0.4))
                                    )
                                    .background(Circle().fill(.ultraThinMaterial))
                                    .padding(4)
                            }
                            .buttonStyle(.plain)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            showingCompare = true
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
        .sheet(isPresented: $showingCompare) {
            CompareView(
                group: $group,
                onKeeperChanged: onKeeperChanged,
                onToggleMarked: onToggleMarked,
                onDeleteSingleAsset: onDeleteSingleAsset
            )
        }
    }
}
