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
                
                // Badges overlay
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        if isBestShot {
                            Text("Best")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.yellow, in: Capsule())
                        }
                        if isKeeper {
                            Text("Keep")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue, in: Capsule())
                        }
                    }
                    
                    Spacer()
                    
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
                    .background(Color.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 5))
                }
                .padding(6)
            }
        }
        .aspectRatio(1, contentMode: .fit)
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
