//
//  FaceAlignmentEngine.swift
//  PicSmart
//

import Foundation
import CoreGraphics
import CoreImage
import Vision

/// Handles face quality filtering and canonical affine landmark alignment.
/// Normalizes roll angle, pupil baseline, and inter-ocular distance into a 112x112 canonical chip
/// required for high-fidelity facial embedding extraction (InsightFace / MobileFaceNet convention).
final class FaceAlignmentEngine: Sendable {
    static let shared = FaceAlignmentEngine()
    
    /// Target canonical image size expected by MobileFaceNet / ArcFace models.
    static let targetSize = CGSize(width: 112, height: 112)
    
    // Canonical pupil coordinates in 112x112 space (bottom-left coordinate origin for CIImage)
    // Corresponding to top-left (38.29, 51.70) and (73.53, 51.70):
    // In bottom-left: y = 112 - 51.70 = 60.30
    private static let targetLeftEye = CGPoint(x: 38.2946, y: 60.3037)
    private static let targetRightEye = CGPoint(x: 73.5318, y: 60.3037)
    private static let targetMidpoint = CGPoint(x: 55.9132, y: 60.3037)
    private static let targetEyeDistance: CGFloat = 35.2372
    
    private let ciContext: CIContext
    
    private init() {
        self.ciContext = CIContext(options: [
            .useSoftwareRenderer: false,
            .priorityRequestLow: false
        ])
    }
    
    /// Checks whether a face observation passes quality and pose gating requirements.
    func passesQualityGates(
        observation: VNFaceObservation,
        imageWidth: CGFloat,
        imageHeight: CGFloat,
        minDimension: CGFloat = 64.0,
        minQuality: Float = 0.35,
        maxYawAngle: Double = 0.785398 // 45 degrees in radians
    ) -> Bool {
        // 1. Capture quality check
        if let quality = observation.faceCaptureQuality, quality < minQuality {
            return false
        }
        
        // 2. Minimum face pixel size in the source image
        let faceW = observation.boundingBox.width * imageWidth
        let faceH = observation.boundingBox.height * imageHeight
        guard faceW >= minDimension && faceH >= minDimension else {
            return false
        }
        
        // 3. Out-of-plane yaw angle check (reject extreme profiles that lack bilateral landmarks)
        if let yaw = observation.yaw?.doubleValue, abs(yaw) > maxYawAngle {
            return false
        }
        
        return true
    }
    
    /// Generates a roll-aligned and eye-leveled 112x112 face chip from the source image.
    /// Uses landmark affine similarity transformation; falls back to roll-guided bounding box crop if landmarks are unavailable.
    func alignFace(
        from cgImage: CGImage,
        observation: VNFaceObservation
    ) -> CGImage? {
        let imgW = CGFloat(cgImage.width)
        let imgH = CGFloat(cgImage.height)
        guard imgW > 0, imgH > 0 else { return nil }
        
        let ciImage = CIImage(cgImage: cgImage)
        let box = observation.boundingBox
        
        let boxX = box.origin.x * imgW
        let boxY = box.origin.y * imgH
        let boxW = box.size.width * imgW
        let boxH = box.size.height * imgH
        
        // Determine eye coordinates in CIImage space (origin bottom-left)
        var sourceLeftEye: CGPoint?
        var sourceRightEye: CGPoint?
        
        if let leftEye = observation.landmarks?.leftEye,
           let rightEye = observation.landmarks?.rightEye,
           !leftEye.normalizedPoints.isEmpty,
           !rightEye.normalizedPoints.isEmpty {
            sourceLeftEye = calculateRegionCentroid(leftEye, boxX: boxX, boxY: boxY, boxW: boxW, boxH: boxH)
            sourceRightEye = calculateRegionCentroid(rightEye, boxX: boxX, boxY: boxY, boxW: boxW, boxH: boxH)
        }
        
        let transform: CGAffineTransform
        
        if let left = sourceLeftEye, let right = sourceRightEye {
            // Landmark-based similarity affine alignment
            let deltaX = right.x - left.x
            let deltaY = right.y - left.y
            let currentEyeDistance = sqrt(deltaX * deltaX + deltaY * deltaY)
            guard currentEyeDistance > 1.0 else { return nil }
            
            let scale = Self.targetEyeDistance / currentEyeDistance
            let angle = atan2(deltaY, deltaX)
            let srcMidpoint = CGPoint(x: (left.x + right.x) * 0.5, y: (left.y + right.y) * 0.5)
            
            // Transform sequence:
            // 1. Move source midpoint to origin
            // 2. Scale to canonical eye distance
            // 3. Rotate by -angle to level the eyes horizontally
            // 4. Translate to target midpoint in 112x112 canvas
            var t = CGAffineTransform.identity
            t = t.translatedBy(x: Self.targetMidpoint.x, y: Self.targetMidpoint.y)
            t = t.rotated(by: -angle)
            t = t.scaledBy(x: scale, y: scale)
            t = t.translatedBy(x: -srcMidpoint.x, y: -srcMidpoint.y)
            transform = t
        } else {
            // Fallback: roll-compensated bounding box alignment
            let centerX = boxX + boxW * 0.5
            let centerY = boxY + boxH * 0.5
            let roll = observation.roll?.doubleValue ?? 0.0
            let maxDim = max(boxW, boxH)
            guard maxDim > 1.0 else { return nil }
            let scale = (Self.targetSize.width * 0.75) / maxDim
            
            var t = CGAffineTransform.identity
            t = t.translatedBy(x: Self.targetSize.width * 0.5, y: Self.targetSize.height * 0.5)
            t = t.rotated(by: -CGFloat(roll))
            t = t.scaledBy(x: scale, y: scale)
            t = t.translatedBy(x: -centerX, y: -centerY)
            transform = t
        }
        
        // Apply transform, clamp image edges to prevent black borders, and crop to 112x112
        let targetRect = CGRect(origin: .zero, size: Self.targetSize)
        let transformed = ciImage.clampedToExtent().transformed(by: transform)
        let cropped = transformed.cropped(to: targetRect)
        
        return ciContext.createCGImage(cropped, from: targetRect)
    }
    
    private func calculateRegionCentroid(
        _ region: VNFaceLandmarkRegion2D,
        boxX: CGFloat,
        boxY: CGFloat,
        boxW: CGFloat,
        boxH: CGFloat
    ) -> CGPoint {
        let pts = region.normalizedPoints
        guard !pts.isEmpty else { return .zero }
        
        var sumX: CGFloat = 0
        var sumY: CGFloat = 0
        for pt in pts {
            sumX += CGFloat(pt.x)
            sumY += CGFloat(pt.y)
        }
        let normCount = CGFloat(pts.count)
        let avgNormX = sumX / normCount
        let avgNormY = sumY / normCount
        
        return CGPoint(
            x: boxX + avgNormX * boxW,
            y: boxY + avgNormY * boxH
        )
    }
}
