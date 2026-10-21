//
//  MatrixDownsampler.swift
//  PicSmart
//

import CoreGraphics
import Foundation

struct MatrixDownsampler: Sendable {
    /// Result of downsampling containing pixels and luminance
    struct MatrixResult: Sendable {
        let pixels: [UInt8]
        let width: Int
        let height: Int
        let averageLuminance: UInt8
    }
    
    /// Downsamples a CGImage to a target grayscale matrix using medium interpolation (low-pass filter).
    static func downsampleToGrayscale(image: CGImage, targetWidth: Int = 9, targetHeight: Int = 8) -> MatrixResult? {
        var pixelBuffer = [UInt8](repeating: 0, count: targetWidth * targetHeight)
        
        guard let context = CGContext(
            data: &pixelBuffer,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: targetWidth,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }
        
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        
        let sum = pixelBuffer.reduce(0) { $0 + Int($1) }
        let avgLuma = UInt8(sum / max(1, pixelBuffer.count))
        
        return MatrixResult(
            pixels: pixelBuffer,
            width: targetWidth,
            height: targetHeight,
            averageLuminance: avgLuma
        )
    }
}
