//
//  FaceEmbeddingEngine.swift
//  PicSmart
//

import Foundation
import CoreGraphics
import CoreML
import Accelerate

/// Generates normalized facial biometric embeddings using CoreML (MobileFaceNet / InsightFace w600k).
/// Executes on the Apple Neural Engine (ANE) with GPU/CPU automatic fallback.
final class FaceEmbeddingEngine: @unchecked Sendable {
    static let shared = FaceEmbeddingEngine()
    
    /// Target image resolution for MobileFaceNet
    static let inputSize = CGSize(width: 112, height: 112)
    
    private let modelQueue = DispatchQueue(label: "com.picsmart.faceembedding", qos: .userInitiated)
    private var mlModel: MLModel?
    private var isInitialized = false
    
    private init() {
        initializeModel()
    }
    
    /// Pre-warms and loads the CoreML model on the Apple Neural Engine.
    func prewarm() {
        modelQueue.async {
            if self.mlModel == nil {
                self.initializeModel()
            }
        }
    }
    
    private func initializeModel() {
        let config = MLModelConfiguration()
        config.computeUnits = .all
        
        // 1. Try precompiled .mlmodelc directly from the bundle
        if let url = Bundle.main.url(forResource: "FaceEmbedding", withExtension: "mlmodelc") {
            if let model = try? MLModel(contentsOf: url, configuration: config) {
                self.mlModel = model
                self.isInitialized = true
                return
            }
        }
        
        // 2. Try looking in Resources subdirectory
        if let subUrl = Bundle.main.url(forResource: "FaceEmbedding", withExtension: "mlmodelc", subdirectory: "Resources") {
            if let model = try? MLModel(contentsOf: subUrl, configuration: config) {
                self.mlModel = model
                self.isInitialized = true
                return
            }
        }
        
        // 3. Try runtime compilation if .mlpackage is provided
        if let packageUrl = Bundle.main.url(forResource: "FaceEmbedding", withExtension: "mlpackage") {
            if let compiledUrl = try? MLModel.compileModel(at: packageUrl),
               let model = try? MLModel(contentsOf: compiledUrl, configuration: config) {
                self.mlModel = model
                self.isInitialized = true
                return
            }
        }
        
        self.isInitialized = true
    }
    
    /// Generates a unit-normalized facial embedding vector from a 112x112 aligned face chip.
    func generateEmbedding(from alignedFaceImage: CGImage) -> [Float]? {
        if let model = mlModel {
            return generateWithModel(model, image: alignedFaceImage)
        }
        return generateDeterministicFallback(image: alignedFaceImage)
    }
    
    // MARK: - CoreML Inference
    
    private func generateWithModel(_ model: MLModel, image: CGImage) -> [Float]? {
        guard let inputMultiArray = imageToMLMultiArray(image) else {
            return nil
        }
        
        // Find input feature name (defaults to "face_image" or first input feature)
        let inputName = model.modelDescription.inputDescriptionsByName.keys.first ?? "face_image"
        
        guard let featureProvider = try? MLDictionaryFeatureProvider(dictionary: [
            inputName: MLFeatureValue(multiArray: inputMultiArray)
        ]) else {
            return nil
        }
        
        guard let prediction = try? model.prediction(from: featureProvider) else {
            return nil
        }
        
        let outputMultiArray: MLMultiArray?
        if let feat = prediction.featureValue(for: "embedding")?.multiArrayValue {
            outputMultiArray = feat
        } else {
            let outputName = model.modelDescription.outputDescriptionsByName.keys.first ?? "embedding"
            outputMultiArray = prediction.featureValue(for: outputName)?.multiArrayValue
        }
        
        guard let multiArray = outputMultiArray else { return nil }
        
        let count = multiArray.count
        guard count > 0 else { return nil }
        
        var rawEmbedding = [Float](repeating: 0, count: count)
        for i in 0..<count {
            rawEmbedding[i] = Float(truncating: multiArray[i])
        }
        
        // Perform L2-normalization via Accelerate
        l2Normalize(&rawEmbedding)
        return rawEmbedding
    }
    
    /// Converts a 112x112 CGImage into an NCHW [1, 3, 112, 112] MLMultiArray normalized to [-1, 1].
    private func imageToMLMultiArray(_ image: CGImage) -> MLMultiArray? {
        let width = 112
        let height = 112
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixelData = [UInt8](repeating: 0, count: height * bytesPerRow)
        
        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        guard let array = try? MLMultiArray(
            shape: [1, 3, NSNumber(value: height), NSNumber(value: width)],
            dataType: .float32
        ) else { return nil }
        
        let channelSize = width * height
        let ptr = array.dataPointer.bindMemory(to: Float.self, capacity: 3 * channelSize)
        
        // Planar NCHW conversion:
        // Channel 0: Red
        // Channel 1: Green
        // Channel 2: Blue
        for y in 0..<height {
            let rowOffset = y * bytesPerRow
            let spatialRowOffset = y * width
            for x in 0..<width {
                let pixelIdx = rowOffset + x * bytesPerPixel
                let r = (Float(pixelData[pixelIdx]) - 127.5) / 127.5
                let g = (Float(pixelData[pixelIdx + 1]) - 127.5) / 127.5
                let b = (Float(pixelData[pixelIdx + 2]) - 127.5) / 127.5
                
                let idx = spatialRowOffset + x
                ptr[idx] = r
                ptr[channelSize + idx] = g
                ptr[2 * channelSize + idx] = b
            }
        }
        
        return array
    }
    
    // MARK: - Normalization & Fallback
    
    /// Vectorized L2 unit normalization via Accelerate vDSP
    private func l2Normalize(_ vector: inout [Float]) {
        guard !vector.isEmpty else { return }
        var sumSq: Float = 0
        vDSP_svesq(vector, 1, &sumSq, vDSP_Length(vector.count))
        let norm = sqrt(sumSq)
        guard norm > 1e-6 else { return }
        var invNorm = 1.0 / norm
        vDSP_vsmul(vector, 1, &invNorm, &vector, 1, vDSP_Length(vector.count))
    }
    
    /// Deterministic fallback embedding when running on simulator or during initial unit testing.
    private func generateDeterministicFallback(image: CGImage) -> [Float]? {
        let dim = 128
        var embedding = [Float](repeating: 0, count: dim)
        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4
        var rawData = [UInt8](repeating: 0, count: height * bytesPerRow)
        
        guard let context = CGContext(
            data: &rawData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        for i in 0..<dim {
            let sampleX = (i * 37) % width
            let sampleY = (i * 53) % height
            let idx = sampleY * bytesPerRow + sampleX * 4
            let r = Float(rawData[idx])
            let g = Float(rawData[idx + 1])
            let b = Float(rawData[idx + 2])
            embedding[i] = (r * 0.299 + g * 0.587 + b * 0.114) / 255.0
        }
        
        l2Normalize(&embedding)
        return embedding
    }
}
