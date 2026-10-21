//
//  LargeVideosView.swift
//  PicSmart
//

import SwiftUI
import Photos

struct LargeVideosView: View {
    @Environment(AppSettings.self) private var settings
    @State private var viewModel = MediaCollectionViewModel(category: .largeVideos)
    @State private var selectedAsset: PHAsset?
    
    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]
    
    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()
            
            if viewModel.isLoading && viewModel.largeVideoAssets.isEmpty {
                ScanningProgressView(
                    category: .largeVideos,
                    progress: viewModel.progress,
                    statusMessage: viewModel.progressMessage,
                    onCancel: {
                        viewModel.cancel()
                    }
                )
            } else if viewModel.largeVideoAssets.isEmpty {
                ContentUnavailableView(
                    "No Large Videos Found",
                    systemImage: GalleryCategory.largeVideos.iconName,
                    description: Text("No videos exceeding \(AppSettings.formatMB(settings.largeVideoThresholdMB)) found. You can adjust this in Settings.")
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        // Summary Bar
                        HStack {
                            Text("\(viewModel.largeVideoAssets.count) items")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            
                            Text("(≥ \(AppSettings.formatMB(settings.largeVideoThresholdMB)))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            Spacer()
                            
                            let totalBytes = viewModel.fileSizes.values.reduce(0, +)
                            if totalBytes > 0 {
                                Text("Total: \(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file))")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(Array(viewModel.largeVideoAssets.enumerated()), id: \.element.localIdentifier) { index, asset in
                                let sizeText = viewModel.fileSizes[asset.localIdentifier].map {
                                    ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
                                }
                                
                                ThumbnailView(
                                    asset: asset,
                                    badgeText: sizeText
                                )
                                .onTapGesture {
                                    selectedAsset = asset
                                }
                                .onAppear {
                                    viewModel.prefetch(around: index)
                                }
                            }
                        }
                    }
                }
                .refreshable {
                    viewModel.load()
                }
            }
        }
        .navigationTitle("Large Videos")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.onAppear()
        }
        .onDisappear {
            viewModel.onDisappear()
        }
        .sheet(item: $selectedAsset) { asset in
            FullScreenAssetView(asset: asset)
        }
    }
}
