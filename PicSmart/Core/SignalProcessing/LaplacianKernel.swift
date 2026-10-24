//
//  LaplacianKernel.swift
//  PicSmart
//

import CoreGraphics
import Foundation

struct LaplacianKernel: Sendable {
    
    /// Computes both the peak tile sharpness (90th percentile) and global variance
    /// using localized grid max-pooling.
    ///
    /// By dividing the image into an 8x8 grid (64 localized tiles), the peak tile sharpness
    /// identifies focal subjects (eyes, faces, flowers, horizons) and prevents false positives
    /// on portraits with background bokeh, minimalist skies, and macro photography.
    nonisolated static func computePeakTileSharpnessVariance(
        from image: CGImage,
        dimension: Int = 512,
        tileGridSize: Int = 8
    ) -> (peakVariance: Double, globalVariance: Double) {
        let width = dimension
        let height = dimension
        
        guard let matrix = MatrixDownsampler.downsampleToGrayscale(
            image: image,
            targetWidth: width,
            targetHeight: height,
            interpolationQuality: .high
        ) else {
            return (0.0, 0.0)
        }
        
        let pixels = matrix.pixels
        let tileW = (width - 2) / tileGridSize
        let tileH = (height - 2) / tileGridSize
        guard tileW > 2, tileH > 2 else {
            let global = computeSharpnessVariance(from: image, dimension: 256, interpolationQuality: .high)
            return (global, global)
        }
        
        var tileResponses: [[Double]] = Array(
            repeating: [Double](),
            count: tileGridSize * tileGridSize
        )
        for i in 0..<tileResponses.count {
            tileResponses[i].reserveCapacity(tileW * tileH)
        }
        
        var allResponses = [Double]()
        allResponses.reserveCapacity((width - 2) * (height - 2))
        
        // 3x3 Laplacian discrete second derivative kernel:
        // [ 0,  1,  0 ]
        // [ 1, -4,  1 ]
        // [ 0,  1,  0 ]
        for y in 1..<(height - 1) {
            let tileY = min(tileGridSize - 1, (y - 1) / tileH)
            let rowOffset = y * width
            let topOffset = (y - 1) * width
            let bottomOffset = (y + 1) * width
            
            for x in 1..<(width - 1) {
                let tileX = min(tileGridSize - 1, (x - 1) / tileW)
                let tileIdx = tileY * tileGridSize + tileX
                
                let center = Double(pixels[rowOffset + x])
                let top    = Double(pixels[topOffset + x])
                let bottom = Double(pixels[bottomOffset + x])
                let left   = Double(pixels[rowOffset + (x - 1)])
                let right  = Double(pixels[rowOffset + (x + 1)])
                
                let val = (top + bottom + left + right) - (4.0 * center)
                tileResponses[tileIdx].append(val)
                allResponses.append(val)
            }
        }
        
        // Global variance
        let globalMean = allResponses.reduce(0.0, +) / Double(max(1, allResponses.count))
        let globalVariance = allResponses.reduce(0.0) { sum, val in
            let diff = val - globalMean
            return sum + (diff * diff)
        } / Double(max(1, allResponses.count))
        
        // Compute variance per tile
        var tileVariances = [Double]()
        tileVariances.reserveCapacity(tileResponses.count)
        
        for response in tileResponses where response.count > 4 {
            let mean = response.reduce(0.0, +) / Double(response.count)
            let variance = response.reduce(0.0) { sum, val in
                let diff = val - mean
                return sum + (diff * diff)
            } / Double(response.count)
            tileVariances.append(variance)
        }
        
        guard !tileVariances.isEmpty else {
            return (globalVariance, globalVariance)
        }
        
        // Sort tiles descending to extract peak focal sharpness (top 10% / 90th percentile)
        tileVariances.sort(by: >)
        let topCount = max(2, tileVariances.count / 10)
        let topTiles = tileVariances.prefix(topCount)
        let peakVariance = topTiles.reduce(0.0, +) / Double(topTiles.count)
        
        return (peakVariance, globalVariance)
    }
    
    /// Computes the statistical variance of the Laplacian second derivative across the whole image.
    nonisolated static func computeSharpnessVariance(
        from image: CGImage,
        dimension: Int = 256,
        interpolationQuality: CGInterpolationQuality = .high
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
        
        for y in 1..<(height - 1) {
            let rowOffset = y * width
            let topOffset = (y - 1) * width
            let bottomOffset = (y + 1) * width
            for x in 1..<(width - 1) {
                let center = Double(pixels[rowOffset + x])
                let top    = Double(pixels[topOffset + x])
                let bottom = Double(pixels[bottomOffset + x])
                let left   = Double(pixels[rowOffset + (x - 1)])
                let right  = Double(pixels[rowOffset + (x + 1)])
                
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
