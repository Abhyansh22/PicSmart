//
//  LaplacianKernel.swift
//  PicSmart
//

import CoreGraphics
import Foundation

struct LaplacianKernel: Sendable {
    /// Computes the statistical variance of the Laplacian second derivative on a thumbnail.
    /// Higher variance indicates sharp focus and clear edges; low variance indicates blur.
    static func computeSharpnessVariance(from image: CGImage) -> Double {
        let width = 32
        let height = 32
        guard let matrix = MatrixDownsampler.downsampleToGrayscale(image: image, targetWidth: width, targetHeight: height) else {
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
