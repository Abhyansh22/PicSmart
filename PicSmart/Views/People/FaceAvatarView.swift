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
            await loadCroppedFace()
        }
    }
    
    private func loadCroppedFace() async {
        guard let cgImage = await ThumbnailService.shared.requestFastAnalysisThumbnail(
            for: asset,
            targetSize: CGSize(width: size * 2.5, height: size * 2.5)
        ) else {
            return
        }
        
        let imgW = CGFloat(cgImage.width)
        let imgH = CGFloat(cgImage.height)
        
        // Vision boundingBox has (0,0) at bottom-left
        let x = faceBoundingBox.origin.x * imgW
        let y = (1.0 - faceBoundingBox.origin.y - faceBoundingBox.size.height) * imgH
        let w = faceBoundingBox.size.width * imgW
        let h = faceBoundingBox.size.height * imgH
        
        // Expand to a balanced square portrait chip (include hair, ears, chin)
        let side = max(w, h) * 1.45
        let centerX = x + w / 2
        let centerY = y + h / 2
        
        let cropX = max(0, min(imgW - side, centerX - side / 2))
        let cropY = max(0, min(imgH - side, centerY - side / 2))
        let cropRect = CGRect(
            x: cropX,
            y: cropY,
            width: min(side, imgW - cropX),
            height: min(side, imgH - cropY)
        )
        
        if let cropped = cgImage.cropping(to: cropRect) {
            self.croppedFaceImage = UIImage(cgImage: cropped)
        }
    }
}
