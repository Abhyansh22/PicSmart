//
//  DifferenceHash.swift
//  PicSmart
//

import CoreGraphics
import Foundation

struct DifferenceHash: Sendable {
    /// Computes a 64-bit horizontal gradient difference hash (dHash) from a 9x8 grayscale image.
    /// 8 rows x 8 horizontal transitions = 64 bits stored in a single UInt64 register.
    nonisolated static func compute(from image: CGImage) -> (hash: UInt64, luma: UInt8)? {
        guard let matrix = MatrixDownsampler.downsampleToGrayscale(image: image, targetWidth: 9, targetHeight: 8) else {
            return nil
        }
        
        let pixels = matrix.pixels
        let width = 9
        let height = 8
        var hash: UInt64 = 0
        var bitPosition = 0
        
        for row in 0..<height {
            for col in 0..<(width - 1) {
                let leftPixel = pixels[row * width + col]
                let rightPixel = pixels[row * width + col + 1]
                if leftPixel > rightPixel {
                    hash |= (1 << UInt64(bitPosition))
                }
                bitPosition += 1
            }
        }
        
        return (hash, matrix.averageLuminance)
    }
    
    /// Computes the Hamming distance between two 64-bit gradient hashes.
    /// Compiles directly to ARM64 hardware population count instruction (`CNT`).
    @inline(__always)
    static func hammingDistance(_ a: UInt64, _ b: UInt64) -> Int {
        (a ^ b).nonzeroBitCount
    }
}
