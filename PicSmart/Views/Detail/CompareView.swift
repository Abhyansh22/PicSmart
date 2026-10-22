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
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedIndex: Int = 0
    
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
                                        Label("Keeper", systemImage: "checkmark.circle.fill")
                                            .font(.caption.weight(.semibold))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(Color.blue, in: Capsule())
                                            .foregroundStyle(.white)
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
                            .padding(.bottom, 8)
                        }
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))
                
                // Bottom filmstrip to switch keeper
                VStack(spacing: 12) {
                    Text("Tap an image below to mark it as the Keeper")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Array(group.assets.enumerated()), id: \.element.localIdentifier) { index, asset in
                                let isKeeper = asset.localIdentifier == group.keeperId
                                Button {
                                    group.keeperId = asset.localIdentifier
                                    onKeeperChanged?(asset.localIdentifier)
                                    selectedIndex = index
                                } label: {
                                    ThumbnailView(
                                        asset: asset,
                                        isKeeper: isKeeper,
                                        isBestShot: asset.localIdentifier == group.bestShotId
                                    )
                                    .frame(width: 72, height: 72)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(isKeeper ? Color.blue : Color.clear, lineWidth: 3)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical, 16)
                .background(Color(uiColor: .secondarySystemBackground))
            }
            .navigationTitle("Compare & Select Keeper")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
