//
//  CompareView.swift
//  PicSmart
//

import SwiftUI
import Photos

struct CompareView: View {
    @Binding var group: AssetGroup
    var onKeeperChanged: ((String) -> Void)?
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedIndex: Int = 0
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Main photo preview
                TabView(selection: $selectedIndex) {
                    ForEach(Array(group.assets.enumerated()), id: \.element.localIdentifier) { index, asset in
                        VStack {
                            ThumbnailView(
                                asset: asset,
                                isKeeper: asset.localIdentifier == group.keeperId,
                                isBestShot: asset.localIdentifier == group.bestShotId
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .padding()
                            
                            HStack(spacing: 16) {
                                Label(asset.formattedDimensions, systemImage: "aspectratio")
                                if let size = group.fileSizes[asset.localIdentifier] {
                                    Label(ByteCountFormatter.string(fromByteCount: size, countStyle: .file), systemImage: "internaldrive")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
