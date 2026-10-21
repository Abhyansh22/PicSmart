//
//  FullScreenAssetView.swift
//  PicSmart
//

import SwiftUI
import Photos
import AVKit

struct FullScreenAssetView: View {
    let asset: PHAsset
    @Environment(\.dismiss) private var dismiss
    
    @State private var fullImage: UIImage?
    @State private var player: AVPlayer?
    @State private var isLoading = true
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if asset.mediaType == .video {
                    if let p = player {
                        VideoPlayer(player: p)
                            .ignoresSafeArea()
                            .onAppear { p.play() }
                            .onDisappear { p.pause() }
                    } else if isLoading {
                        ProgressView()
                            .tint(.white)
                    }
                } else {
                    if let image = fullImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                    } else if isLoading {
                        ProgressView()
                            .tint(.white)
                    }
                }
            }
            .navigationTitle(asset.creationDate?.formatted(date: .abbreviated, time: .shortened) ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
                
                ToolbarItem(placement: .bottomBar) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(asset.formattedDimensions)
                                .font(.caption.weight(.semibold))
                            if let size = asset.formattedFileSize {
                                Text(size)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .foregroundStyle(.white)
                        Spacer()
                    }
                }
            }
            .toolbarBackground(.black.opacity(0.8), for: .navigationBar, .bottomBar)
            .toolbarColorScheme(.dark, for: .navigationBar, .bottomBar)
            .task {
                await loadAsset()
            }
        }
    }
    
    private func loadAsset() async {
        isLoading = true
        if asset.mediaType == .video {
            let options = PHVideoRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                if let urlAsset = avAsset as? AVURLAsset {
                    Task { @MainActor in
                        self.player = AVPlayer(url: urlAsset.url)
                        self.isLoading = false
                    }
                }
            }
        } else {
            let img = await ThumbnailService.shared.requestFullImage(for: asset)
            self.fullImage = img
            self.isLoading = false
        }
    }
}
