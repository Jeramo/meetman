//
//  SpeakerEmbedding.swift
//  MeetingCopilot
//
//  Speaker embedding extraction using Core ML
//

import Accelerate
import AVFoundation
import CoreML
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.jeramo.meetingman", category: "diarization")

/// Embedding vector with time range
public struct Embedding: Sendable, Equatable {
    public let time: ClosedRange<Double>
    public let vector: [Float]

    public init(time: ClosedRange<Double>, vector: [Float]) {
        self.time = time
        self.vector = vector
    }
}

/// Speaker embedder using Core ML model (e.g., ECAPA-TDNN or x-vector)
public final class SpeakerEmbedder: @unchecked Sendable {
    private let model: MLModel?

    /// Initialize with compiled Core ML model
    /// - Parameter compiledModelURL: URL to .mlmodelc bundle
    public init(compiledModelURL: URL?) {
        guard let url = compiledModelURL,
              let loadedModel = try? MLModel(contentsOf: url) else {
            logger.warning("Speaker embedder Core ML model not available at \(compiledModelURL?.path ?? "nil")")
            self.model = nil
            return
        }

        self.model = loadedModel
        logger.info("Speaker embedder initialized with Core ML model")
    }

    /// Check if embedder is available
    public var isAvailable: Bool {
        model != nil
    }

    /// Compute embeddings on sliding windows over a speech region
    ///
    /// - Parameters:
    ///   - pcm: Float PCM samples normalized to [-1, 1]
    ///   - sampleRate: Sample rate in Hz
    ///   - windowSeconds: Window size in seconds (default 1.5s)
    ///   - hopSeconds: Hop size in seconds (default 0.75s)
    ///   - region: Speech region to process
    /// - Returns: Array of embeddings
    public func embed(
        pcm: [Float],
        sampleRate: Double,
        windowSeconds: Double = 1.5,
        hopSeconds: Double = 0.75,
        region: VADRegion
    ) throws -> [Embedding] {
        guard let model = model else {
            throw DiarizationError.embedderUnavailable
        }

        let windowSize = Int(sampleRate * windowSeconds)
        let hopSize = Int(sampleRate * hopSeconds)
        let startSample = Int(region.start * sampleRate)
        let endSample = Int(region.end * sampleRate)

        guard endSample <= pcm.count else {
            throw DiarizationError.invalidAudioRange
        }

        var embeddings: [Embedding] = []
        var i = startSample

        while i + windowSize <= endSample {
            let segment = Array(pcm[i..<i + windowSize])

            // Pre-process audio (apply pre-emphasis if needed)
            let processed = applyPreEmphasis(segment, alpha: 0.97)

            // Convert to MLMultiArray
            guard let input = try? self.createMLInput(samples: processed) else {
                logger.warning("Failed to create ML input for window at \(i)")
                i += hopSize
                continue
            }

            // Run inference
            guard let output = try? model.prediction(from: input),
                  let embeddingArray = output.featureValue(for: "embedding")?.multiArrayValue else {
                logger.warning("Failed to extract embedding at window \(i)")
                i += hopSize
                continue
            }

            // Convert to Float array
            let vector = embeddingArray.toFloatArray()

            // Normalize embedding to unit length (L2 norm)
            let normalized = normalizeVector(vector)

            let timeRange = (Double(i) / sampleRate)...(Double(i + windowSize) / sampleRate)
            embeddings.append(Embedding(time: timeRange, vector: normalized))

            i += hopSize
        }

        logger.debug("Extracted \(embeddings.count) embeddings from region [\(region.start, privacy: .public)..\(region.end, privacy: .public)]")
        return embeddings
    }

    // MARK: - Private Helpers

    /// Apply pre-emphasis filter to enhance high frequencies
    private func applyPreEmphasis(_ samples: [Float], alpha: Float = 0.97) -> [Float] {
        guard samples.count > 1 else { return samples }

        var result = [Float](repeating: 0, count: samples.count)
        result[0] = samples[0]

        for i in 1..<samples.count {
            result[i] = samples[i] - alpha * samples[i - 1]
        }

        return result
    }

    /// Create MLFeatureProvider from audio samples
    /// Assumes model expects "audio" input as 1D float array
    private func createMLInput(samples: [Float]) throws -> MLFeatureProvider {
        let shape = [NSNumber(value: samples.count)]
        let array = try MLMultiArray(shape: shape, dataType: .float32)

        for (index, value) in samples.enumerated() {
            array[index] = NSNumber(value: value)
        }

        return try MLDictionaryFeatureProvider(dictionary: ["audio": array])
    }

    /// Normalize vector to unit length (L2 normalization)
    private func normalizeVector(_ vector: [Float]) -> [Float] {
        var sum: Float = 0
        vDSP_svesq(vector, 1, &sum, vDSP_Length(vector.count))

        let magnitude = sqrtf(sum)
        guard magnitude > 0 else { return vector }

        var normalized = [Float](repeating: 0, count: vector.count)
        var divisor = magnitude
        vDSP_vsdiv(vector, 1, &divisor, &normalized, 1, vDSP_Length(vector.count))

        return normalized
    }
}

// MARK: - MLMultiArray Extension

extension MLMultiArray {
    /// Convert MLMultiArray to Float array
    func toFloatArray() -> [Float] {
        let count = self.count
        var result = [Float](repeating: 0, count: count)

        for i in 0..<count {
            result[i] = Float(truncating: self[i])
        }

        return result
    }
}

// MARK: - Errors

public enum DiarizationError: LocalizedError {
    case embedderUnavailable
    case invalidAudioRange
    case clusteringFailed
    case alignmentFailed

    public var errorDescription: String? {
        switch self {
        case .embedderUnavailable:
            return "Speaker embedder Core ML model not available"
        case .invalidAudioRange:
            return "Invalid audio range for embedding extraction"
        case .clusteringFailed:
            return "Failed to cluster speaker embeddings"
        case .alignmentFailed:
            return "Failed to align diarization with ASR segments"
        }
    }
}
