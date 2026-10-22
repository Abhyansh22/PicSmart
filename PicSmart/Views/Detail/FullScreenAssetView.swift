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
    
    @State private var player: AVPlayer?
    @State private var isVideoLoading = true
    
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
                    } else if isVideoLoading {
                        ProgressView()
                            .tint(.white)
                    }
                } else {
                    HighResolutionAssetImage(asset: asset, allowZoom: true)
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
                if asset.mediaType == .video {
                    await loadVideo()
                }
            }
        }
    }
    
    private func loadVideo() async {
        isVideoLoading = true
        let options = PHVideoRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        
        PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
            if let urlAsset = avAsset as? AVURLAsset {
                Task { @MainActor in
                    self.player = AVPlayer(url: urlAsset.url)
                    self.isVideoLoading = false
                }
            }
        }
    }
}
