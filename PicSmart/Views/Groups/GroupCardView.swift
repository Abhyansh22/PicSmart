//
//  GroupCardView.swift
//  PicSmart
//

import SwiftUI
import Photos

struct GroupCardView: View {
    @Binding var group: AssetGroup
    var onKeeperChanged: ((String) -> Void)?
    var onDeleteGroup: (() -> Void)?
    
    @State private var showingCompare = false
    @State private var isDeleting = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Group Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(group.assets.count) items")
                        .font(.subheadline.weight(.semibold))
                    
                    if group.savingsBytes > 0 {
                        Text("Save ~\(ByteCountFormatter.string(fromByteCount: group.savingsBytes, countStyle: .file))")
                            .font(.caption)
                            .foregroundStyle(.green)
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
                    Image(systemName: "trash")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.red)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            
            // Thumbnails strip
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(group.assets) { asset in
                        let isKeeper = asset.localIdentifier == group.keeperId
                        let isBest = asset.localIdentifier == group.bestShotId
                        
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
                                .stroke(isKeeper ? Color.blue : Color.clear, lineWidth: 2.5)
                        )
                        .onTapGesture {
                            showingCompare = true
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
            CompareView(group: $group, onKeeperChanged: onKeeperChanged)
        }
    }
}
