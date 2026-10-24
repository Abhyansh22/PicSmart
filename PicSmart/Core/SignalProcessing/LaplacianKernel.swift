//
//  LaplacianKernel.swift
//  PicSmart
//

import CoreGraphics
import Foundation

struct LaplacianKernel: Sendable {
    /// Computes the statistical variance of the Laplacian second derivative on a thumbnail.
    /// Higher variance indicates sharp focus and clear edges; low variance indicates blur.
    ///
    /// - Parameters:
    ///   - image: The source image to analyse. Should be a high-fidelity thumbnail (`.highQualityFormat` + `.exact`)
    ///     for accurate blur detection. Do NOT use `.fastFormat` thumbnails — JPEG block artifacts will corrupt results.
    ///   - dimension: The size of the grayscale matrix to downsample to before applying the kernel.
    ///     256 is recommended for blur analysis; 32 is sufficient for hashing.
    ///   - interpolationQuality: The CGInterpolationQuality used when downsampling to the analysis matrix.
    ///     Use `.high` for blur detection to preserve edge frequency content. Defaults to `.medium` for hash scans.
    nonisolated static func computeSharpnessVariance(
        from image: CGImage,
        dimension: Int = 32,
        interpolationQuality: CGInterpolationQuality = .medium
    ) -> Double {
        let width = dimension
        let height = dimension
        guard let matrix = MatrixDownsampler.downsampleToGrayscale(
            image: image,
            targetWidth: width,
            targetHeight: height,
            interpolationQuality: interpolationQuality
        ) else {
            return 0.0
        }
        
        let pixels = matrix.pixels
        var response = [Double]()
        response.reserveCapacity((width - 2) * (height - 2))
        
        // 3x3 Laplacian Kernel:
        // [ 0,  1,  0 ]
        // [ 1, -4,  1 ]
        // [ 0,  1,  0 ]
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let center = Double(pixels[y * width + x])
                let top    = Double(pixels[(y - 1) * width + x])
                let bottom = Double(pixels[(y + 1) * width + x])
                let left   = Double(pixels[y * width + (x - 1)])
                let right  = Double(pixels[y * width + (x + 1)])
                
                let val = (top + bottom + left + right) - (4.0 * center)
                response.append(val)
            }
        }
        
        guard !response.isEmpty else { return 0.0 }
        
        let mean = response.reduce(0.0, +) / Double(response.count)
        let variance = response.reduce(0.0) { sum, val in
            let diff = val - mean
            return sum + (diff * diff)
        } / Double(response.count)
        
        return variance
    }
}
