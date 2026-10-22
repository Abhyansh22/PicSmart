//
//  ZoomableImageView.swift
//  PicSmart
//

import SwiftUI
import UIKit
import Photos

final class CenteringScrollView: UIScrollView {
    var onLayout: (() -> Void)?
    private var lastBoundsSize: CGSize = .zero
    
    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != lastBoundsSize {
            lastBoundsSize = bounds.size
            onLayout?()
        }
    }
}

struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage
    
    func makeUIView(context: Context) -> CenteringScrollView {
        let scrollView = CenteringScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 4.0
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.bouncesZoom = true
        scrollView.backgroundColor = .clear
        
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.tag = 100
        
        scrollView.addSubview(imageView)
        context.coordinator.imageView = imageView
        context.coordinator.scrollView = scrollView
        
        let coordinator = context.coordinator
        scrollView.onLayout = { [weak coordinator] in
            coordinator?.updateImageFrame()
        }
        
        let doubleTapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTapGesture.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTapGesture)
        
        return scrollView
    }
    
    func updateUIView(_ uiView: CenteringScrollView, context: Context) {
        guard let imageView = uiView.viewWithTag(100) as? UIImageView else { return }
        if imageView.image != image {
            imageView.image = image
            uiView.zoomScale = 1.0
            context.coordinator.updateImageFrame()
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var scrollView: UIScrollView?
        weak var imageView: UIImageView?
        
        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }
        
        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerImage()
        }
        
        func updateImageFrame() {
            guard let scrollView = scrollView, let imageView = imageView, let image = imageView.image else { return }
            
            let boundsSize = scrollView.bounds.size
            guard boundsSize.width > 0, boundsSize.height > 0 else { return }
            
            let imageSize = image.size
            guard imageSize.width > 0, imageSize.height > 0 else { return }
            
            let widthScale = boundsSize.width / imageSize.width
            let heightScale = boundsSize.height / imageSize.height
            let minScale = min(widthScale, heightScale)
            
            let displaySize = CGSize(width: imageSize.width * minScale, height: imageSize.height * minScale)
            imageView.frame = CGRect(origin: .zero, size: displaySize)
            scrollView.contentSize = displaySize
            centerImage()
        }
        
        func centerImage() {
            guard let scrollView = scrollView, let imageView = imageView else { return }
            let boundsSize = scrollView.bounds.size
            var frameToCenter = imageView.frame
            
            if frameToCenter.size.width < boundsSize.width {
                frameToCenter.origin.x = (boundsSize.width - frameToCenter.size.width) / 2
            } else {
                frameToCenter.origin.x = 0
            }
            
            if frameToCenter.size.height < boundsSize.height {
                frameToCenter.origin.y = (boundsSize.height - frameToCenter.size.height) / 2
            } else {
                frameToCenter.origin.y = 0
            }
            
            imageView.frame = frameToCenter
        }
        
        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = scrollView else { return }
            if scrollView.zoomScale > 1.0 {
                scrollView.setZoomScale(1.0, animated: true)
            } else {
                let pointInView = gesture.location(in: imageView)
                let newZoomScale: CGFloat = 2.5
                let scrollViewSize = scrollView.bounds.size
                let w = scrollViewSize.width / newZoomScale
                let h = scrollViewSize.height / newZoomScale
                let x = pointInView.x - (w / 2.0)
                let y = pointInView.y - (h / 2.0)
                let rectToZoomTo = CGRect(x: x, y: y, width: w, height: h)
                scrollView.zoom(to: rectToZoomTo, animated: true)
            }
        }
    }
}

/// Progressive two-tier high-resolution asset image view.
/// Shows instant preview (~520px) while non-degraded full-res image loads in background.
struct HighResolutionAssetImage: View {
    let asset: PHAsset
    var allowZoom: Bool = true
    
    @State private var previewImage: UIImage?
    @State private var fullImage: UIImage?
    @State private var isLoading = true
    
    var body: some View {
        ZStack {
            if let full = fullImage {
                if allowZoom {
                    ZoomableImageView(image: full)
                } else {
                    Image(uiImage: full)
                        .resizable()
                        .scaledToFit()
                }
            } else if let preview = previewImage {
                if allowZoom {
                    ZoomableImageView(image: preview)
                } else {
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFit()
                }
            }
            
            if isLoading && previewImage == nil {
                ProgressView()
                    .tint(.white)
            }
        }
        .task(id: asset.localIdentifier) {
            isLoading = true
            let finalImage = await ThumbnailService.shared.requestFullImage(for: asset) { preview in
                Task { @MainActor in
                    if self.fullImage == nil {
                        self.previewImage = preview
                    }
                }
            }
            if !Task.isCancelled {
                self.fullImage = finalImage
                self.isLoading = false
            }
        }
        .onDisappear {
            // Memory hygiene: unload high-res image buffers when navigating away
            fullImage = nil
            previewImage = nil
        }
    }
}
