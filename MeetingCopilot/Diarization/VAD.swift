//
//  VAD.swift
//  MeetingCopilot
//
//  Voice Activity Detection for speaker diarization
//

import Accelerate
import AVFoundation
import Foundation

/// Time range for a speech region
public struct VADRegion: Sendable, Equatable {
    public let start: TimeInterval
    public let end: TimeInterval

    public init(start: TimeInterval, end: TimeInterval) {
        self.start = start
        self.end = end
    }

    public var duration: TimeInterval {
        end - start
    }
}

/// Voice Activity Detection using energy-based analysis
public enum VAD {

    /// Detect speech regions in PCM audio using energy-based VAD
    ///
    /// - Parameters:
    ///   - pcm: Float PCM samples normalized to [-1, 1]
    ///   - sampleRate: Sample rate in Hz
    ///   - frameMs: Frame size in milliseconds (default 25ms)
    ///   - hopMs: Hop size in milliseconds (default 10ms)
    ///   - energyThreshDB: Energy threshold in dB (default -45dB)
    ///   - minRegion: Minimum speech region duration in seconds (default 0.4s)
    /// - Returns: Array of detected speech regions
    public static func detectSpeechRegions(
        pcm: [Float],
        sampleRate: Double,
        frameMs: Double = 25,
        hopMs: Double = 10,
        energyThreshDB: Float = -45,
        minRegion: Double = 0.4
    ) -> [VADRegion] {
        let frameSize = Int(sampleRate * frameMs / 1000.0)
        let hopSize = Int(sampleRate * hopMs / 1000.0)

        var regions: [VADRegion] = []
        var inSpeech = false
        var startIdx = 0

        var i = 0
        while i + frameSize <= pcm.count {
            let slice = Array(pcm[i..<i + frameSize])

            // Compute RMS energy
            var rms: Float = 0
            vDSP_rmsqv(slice, 1, &rms, vDSP_Length(frameSize))

            // Convert to dB
            let db = 20 * log10f(max(rms, 1e-7))

            if db > energyThreshDB {
                if !inSpeech {
                    inSpeech = true
                    startIdx = i
                }
            } else if inSpeech {
                let endIdx = i
                let duration = Double(endIdx - startIdx) / sampleRate

                if duration >= minRegion {
                    let region = VADRegion(
                        start: Double(startIdx) / sampleRate,
                        end: Double(endIdx) / sampleRate
                    )
                    regions.append(region)
                }
                inSpeech = false
            }

            i += hopSize
        }

        // Handle trailing speech region
        if inSpeech {
            let duration = Double(pcm.count - startIdx) / sampleRate
            if duration >= minRegion {
                let region = VADRegion(
                    start: Double(startIdx) / sampleRate,
                    end: Double(pcm.count) / sampleRate
                )
                regions.append(region)
            }
        }

        return regions
    }

    /// Merge speech regions that are close together
    ///
    /// - Parameters:
    ///   - regions: Input speech regions
    ///   - maxGapSeconds: Maximum gap to merge (default 0.3s)
    /// - Returns: Merged regions
    public static func mergeRegions(
        _ regions: [VADRegion],
        maxGapSeconds: Double = 0.3
    ) -> [VADRegion] {
        guard !regions.isEmpty else { return [] }

        let sorted = regions.sorted { $0.start < $1.start }
        var merged: [VADRegion] = []
        var current = sorted[0]

        for i in 1..<sorted.count {
            let next = sorted[i]
            let gap = next.start - current.end

            if gap <= maxGapSeconds {
                // Merge regions
                current = VADRegion(start: current.start, end: next.end)
            } else {
                // Save current and start new region
                merged.append(current)
                current = next
            }
        }

        merged.append(current)
        return merged
    }
}
