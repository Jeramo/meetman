//
//  Diarizer.swift
//  MeetingCopilot
//
//  Main speaker diarization orchestrator
//

import AVFoundation
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.jeramo.meetingman", category: "diarization")

/// Diarization result: speaker turn with time range
public struct SpeakerTurn: Sendable, Equatable {
    public let start: TimeInterval
    public let end: TimeInterval
    public let speakerID: String

    public init(start: TimeInterval, end: TimeInterval, speakerID: String) {
        self.start = start
        self.end = end
        self.speakerID = speakerID
    }

    public var duration: TimeInterval {
        end - start
    }

    /// Check if this turn contains a given timestamp
    public func contains(_ time: TimeInterval) -> Bool {
        start <= time && time <= end
    }

    /// Check if this turn overlaps with a time range
    public func overlaps(start: TimeInterval, end: TimeInterval) -> Bool {
        !(self.end <= start || self.start >= end)
    }
}

/// Speaker diarization engine
public final class Diarizer: @unchecked Sendable {
    private let embedder: SpeakerEmbedder?

    /// Initialize diarizer with optional Core ML embedder
    /// - Parameter embedderURL: URL to compiled .mlmodelc model (nil for heuristic fallback)
    public init(embedderURL: URL? = nil) {
        self.embedder = SpeakerEmbedder(compiledModelURL: embedderURL)

        if embedder?.isAvailable == true {
            logger.info("Diarizer initialized with ML embedder")
        } else {
            logger.info("Diarizer initialized with heuristic fallback (no ML model)")
        }
    }

    /// Perform speaker diarization on audio
    ///
    /// - Parameters:
    ///   - pcm: Float PCM samples normalized to [-1, 1]
    ///   - sampleRate: Sample rate in Hz
    ///   - minTurnDuration: Minimum speaker turn duration in seconds (default 1.0)
    /// - Returns: Array of speaker turns with labels
    public func diarize(
        pcm: [Float],
        sampleRate: Double,
        minTurnDuration: Double = 1.0
    ) -> [SpeakerTurn] {
        logger.info("Starting diarization on \(pcm.count) samples at \(sampleRate)Hz")

        // Step 1: Voice Activity Detection
        let vadRegions = VAD.detectSpeechRegions(
            pcm: pcm,
            sampleRate: sampleRate,
            energyThreshDB: -45,
            minRegion: 0.4
        )

        // Merge close regions
        let mergedRegions = VAD.mergeRegions(vadRegions, maxGapSeconds: 0.3)

        logger.info("VAD detected \(mergedRegions.count) speech regions")

        guard !mergedRegions.isEmpty else {
            logger.warning("No speech detected in audio")
            return []
        }

        // Step 2: Extract embeddings or use fallback
        guard let embedder = embedder, embedder.isAvailable else {
            logger.info("Using heuristic fallback for speaker labeling")
            return heuristicDiarization(from: mergedRegions)
        }

        // Step 3: Extract embeddings from speech regions
        var allEmbeddings: [Embedding] = []

        for region in mergedRegions {
            do {
                let embeddings = try embedder.embed(
                    pcm: pcm,
                    sampleRate: sampleRate,
                    windowSeconds: 1.5,
                    hopSeconds: 0.75,
                    region: region
                )
                allEmbeddings.append(contentsOf: embeddings)
            } catch {
                logger.error("Failed to extract embeddings from region: \(error.localizedDescription)")
            }
        }

        guard !allEmbeddings.isEmpty else {
            logger.warning("No embeddings extracted, falling back to heuristic")
            return heuristicDiarization(from: mergedRegions)
        }

        logger.info("Extracted \(allEmbeddings.count) embeddings")

        // Step 4: Cluster embeddings
        let vectors = allEmbeddings.map { $0.vector }
        let labels = Clustering.agglomerativeCosine(vectors, maxClusters: 6)

        // Step 5: Convert embedding windows to speaker turns
        var turns = convertEmbeddingsToTurns(allEmbeddings, labels: labels)

        // Step 6: Post-process turns (smooth, merge, filter short)
        turns = smoothTurns(turns, minDuration: minTurnDuration)

        logger.info("Diarization complete: \(turns.count) speaker turns")

        return turns
    }

    // MARK: - Private Helpers

    /// Heuristic diarization: alternate speakers based on pauses
    private func heuristicDiarization(from regions: [VADRegion]) -> [SpeakerTurn] {
        var turns: [SpeakerTurn] = []
        var currentSpeaker = 0

        for region in regions {
            let speakerID = "S\(currentSpeaker + 1)"
            turns.append(SpeakerTurn(
                start: region.start,
                end: region.end,
                speakerID: speakerID
            ))

            // Alternate between two speakers
            currentSpeaker = (currentSpeaker + 1) % 2
        }

        return turns
    }

    /// Convert embedding windows with cluster labels to contiguous speaker turns
    private func convertEmbeddingsToTurns(
        _ embeddings: [Embedding],
        labels: [Int]
    ) -> [SpeakerTurn] {
        guard !embeddings.isEmpty, embeddings.count == labels.count else {
            return []
        }

        var turns: [SpeakerTurn] = []
        var i = 0

        while i < embeddings.count {
            let speakerLabel = labels[i]
            let speakerID = "S\(speakerLabel + 1)"

            var start = embeddings[i].time.lowerBound
            var end = embeddings[i].time.upperBound

            // Extend turn while same speaker
            var j = i
            while j + 1 < embeddings.count {
                if labels[j + 1] != speakerLabel {
                    break
                }
                j += 1
                end = max(end, embeddings[j].time.upperBound)
            }

            turns.append(SpeakerTurn(start: start, end: end, speakerID: speakerID))
            i = j + 1
        }

        return turns
    }

    /// Smooth speaker turns using median filtering and merging
    private func smoothTurns(
        _ turns: [SpeakerTurn],
        minDuration: Double
    ) -> [SpeakerTurn] {
        guard !turns.isEmpty else { return [] }

        var smoothed: [SpeakerTurn] = []

        // First pass: merge consecutive turns from same speaker
        var merged: [SpeakerTurn] = []
        var current = turns[0]

        for i in 1..<turns.count {
            let next = turns[i]

            // Merge if same speaker and gap is small
            if next.speakerID == current.speakerID && (next.start - current.end) < 0.5 {
                current = SpeakerTurn(
                    start: current.start,
                    end: next.end,
                    speakerID: current.speakerID
                )
            } else {
                merged.append(current)
                current = next
            }
        }
        merged.append(current)

        // Second pass: filter out very short turns
        for turn in merged {
            if turn.duration >= minDuration {
                smoothed.append(turn)
            } else {
                logger.debug("Filtering out short turn: \(turn.speakerID) [\(turn.start)..\(turn.end)] duration=\(turn.duration)")
            }
        }

        // Third pass: median filter to remove single-frame speaker switches
        if smoothed.count >= 3 {
            smoothed = applyMedianFilter(smoothed)
        }

        return smoothed
    }

    /// Apply median filter to remove isolated speaker switches
    private func applyMedianFilter(_ turns: [SpeakerTurn]) -> [SpeakerTurn] {
        guard turns.count >= 3 else { return turns }

        var filtered: [SpeakerTurn] = []
        filtered.append(turns[0])

        for i in 1..<(turns.count - 1) {
            let prev = turns[i - 1]
            let current = turns[i]
            let next = turns[i + 1]

            // If current speaker is different from both neighbors and turn is short,
            // consider it noise and merge with majority neighbor
            if current.speakerID != prev.speakerID &&
               current.speakerID != next.speakerID &&
               current.duration < 2.0 {

                // Merge with previous turn
                if let last = filtered.last {
                    filtered.removeLast()
                    filtered.append(SpeakerTurn(
                        start: last.start,
                        end: current.end,
                        speakerID: last.speakerID
                    ))
                } else {
                    filtered.append(current)
                }
            } else {
                filtered.append(current)
            }
        }

        filtered.append(turns[turns.count - 1])

        return filtered
    }
}
