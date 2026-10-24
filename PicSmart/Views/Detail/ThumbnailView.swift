//
//  ThumbnailView.swift
//  PicSmart
//

import SwiftUI
import Photos

struct ThumbnailView: View {
    let asset: PHAsset
    var badgeText: String?
    var isKeeper: Bool = false
    var isBestShot: Bool = false
    var isSelectionMode: Bool = false
    var isSelected: Bool = false
    var onToggleSelect: (() -> Void)? = nil
    
    @State private var image: UIImage?
    @State private var requestID: PHImageRequestID?
    
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                if let img = image {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color(uiColor: .secondarySystemBackground))
                        .overlay {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                }
                
                // Top-leading subtle "Best Shot" / "Keeper" badges
                VStack(alignment: .leading, spacing: 4) {
                    if isBestShot {
                        HStack(spacing: 3) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 9, weight: .bold))
                            Text("Best Shot")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(.yellow)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.ultraThinMaterial, in: Capsule())
                    } else if isKeeper {
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 9, weight: .bold))
                            Text("Keeper")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.blue, in: Capsule())
                    }
                    
                    Spacer()
                    
                    // Bottom video duration & file size badge
                    HStack(spacing: 4) {
                        if asset.mediaType == .video {
                            Image(systemName: "play.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(.white)
                            if let dur = asset.formattedDuration {
                                Text(dur)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.white)
                            }
                        }
                        
                        if let badge = badgeText {
                            if asset.mediaType == .video {
                                Text("·")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                            Text(badge)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 5))
                }
                .padding(6)
                
                // Top-trailing Selection Mode Checkbox
                if isSelectionMode {
                    VStack {
                        HStack {
                            Spacer()
                            Button {
                                onToggleSelect?()
                            } label: {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 20, weight: .semibold))
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(
                                        isSelected ? .white : .secondary,
                                        isSelected ? Color.blue : Color.black.opacity(0.4)
                                    )
                                    .background(Circle().fill(.ultraThinMaterial))
                            }
                            .buttonStyle(.plain)
                            .padding(6)
                        }
                        Spacer()
                    }
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelectionMode && isSelected ? Color.blue : Color.clear, lineWidth: 2)
        )
        .onAppear {
            loadImage()
        }
        .onDisappear {
            cancelImage()
        }
    }
    
    private func loadImage() {
        requestID = ThumbnailService.shared.requestThumbnail(
            for: asset,
            targetSize: CGSize(width: 250, height: 250)
        ) { fetchedImage in
            self.image = fetchedImage
        }
    }
    
    private func cancelImage() {
        if let id = requestID {
            ThumbnailService.shared.cancelImageRequest(id)
            requestID = nil
        }
    }
}
