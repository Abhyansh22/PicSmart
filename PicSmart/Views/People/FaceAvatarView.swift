//
//  FaceAvatarView.swift
//  PicSmart
//

import SwiftUI
import Photos

struct FaceAvatarView: View {
    let asset: PHAsset
    let faceBoundingBox: CGRect
    var size: CGFloat = 74
    var isHeroCard: Bool = false
    var cornerRadius: CGFloat = 18
    
    @State private var croppedFaceImage: UIImage?
    
    init(
        asset: PHAsset,
        faceBoundingBox: CGRect,
        size: CGFloat = 74,
        isHeroCard: Bool = false,
        cornerRadius: CGFloat = 18
    ) {
        self.asset = asset
        self.faceBoundingBox = faceBoundingBox
        self.size = size
        self.isHeroCard = isHeroCard
        self.cornerRadius = cornerRadius
        
        // Fast synchronous memory cache lookup to eliminate initial flicker during scrolling
        let key = FaceAvatarCache.shared.key(
            assetIdentifier: asset.localIdentifier,
            boundingBox: faceBoundingBox,
            size: size
        )
        _croppedFaceImage = State(initialValue: FaceAvatarCache.shared.get(key: key))
    }
    
    var body: some View {
        ZStack {
            if let image = croppedFaceImage {
                if isHeroCard {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: size)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                } else {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                }
            } else {
                if isHeroCard {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color(uiColor: .tertiarySystemFill))
                        .frame(maxWidth: .infinity)
                        .frame(height: size)
                    Image(systemName: "person.fill")
                        .font(.system(size: size * 0.35))
                        .foregroundStyle(.secondary)
                } else {
                    Circle()
                        .fill(Color(uiColor: .tertiarySystemFill))
                        .frame(width: size, height: size)
                    Image(systemName: "person.fill")
                        .font(.system(size: size * 0.45))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: isHeroCard ? nil : size, height: size)
        .overlay {
            if isHeroCard {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            } else {
                Circle()
                    .stroke(Color.primary.opacity(0.10), lineWidth: 1.2)
            }
        }
        .shadow(color: .black.opacity(0.04), radius: 3, x: 0, y: 1)
        .task(id: asset.localIdentifier) {
            await loadAvatar()
        }
    }
    
    private func loadAvatar() async {
        let key = FaceAvatarCache.shared.key(
            assetIdentifier: asset.localIdentifier,
            boundingBox: faceBoundingBox,
            size: size
        )
        
        // If already cached, ensure state is set and return
        if let cached = FaceAvatarCache.shared.get(key: key) {
            if croppedFaceImage == nil {
                croppedFaceImage = cached
            }
            return
        }
        
        // Two-Tier progressive loading:
        // Tier 1: onPreview renders an instant medium preview (~400px source) so the view is never blank.
        // Tier 2: high-fidelity face-proportional crop (~1000-1400px source) renders tack-sharp on Retina.
        let highResAvatar = await ThumbnailService.shared.requestFaceAvatar(
            for: asset,
            faceBoundingBox: faceBoundingBox,
            displaySize: size
        ) { preview in
            if croppedFaceImage == nil {
                croppedFaceImage = preview
            }
        }
        
        if let highResAvatar, !Task.isCancelled {
            withAnimation(.easeInOut(duration: 0.15)) {
                croppedFaceImage = highResAvatar
            }
        }
    }
}
