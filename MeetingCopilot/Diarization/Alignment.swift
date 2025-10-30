//
//  Alignment.swift
//  MeetingCopilot
//
//  Align speaker diarization turns with ASR transcript segments
//

import Foundation
import Speech
import OSLog

private let logger = Logger(subsystem: "com.jeramo.meetingman", category: "diarization")

/// Transcript segment with speaker label and timing
public struct LabeledSegment: Sendable, Equatable {
    public let speakerID: String
    public let text: String
    public let start: TimeInterval
    public let end: TimeInterval

    public init(speakerID: String, text: String, start: TimeInterval, end: TimeInterval) {
        self.speakerID = speakerID
        self.text = text
        self.start = start
        self.end = end
    }

    public var duration: TimeInterval {
        end - start
    }
}

/// Speaker alignment utilities
public enum Alignment {

    /// Assign speaker labels to transcript segments by temporal alignment
    ///
    /// Uses maximum overlap strategy: each ASR segment is assigned to the speaker
    /// whose turn has the most temporal overlap with that segment.
    ///
    /// - Parameters:
    ///   - segments: Array of transcript segments with timestamps
    ///   - turns: Array of speaker diarization turns
    /// - Returns: Array of labeled segments with speaker IDs
    public static func label(
        segments: [TranscriptChunkData],
        turns: [SpeakerTurn]
    ) -> [LabeledSegment] {
        guard !segments.isEmpty else {
            logger.warning("No segments to label")
            return []
        }

        guard !turns.isEmpty else {
            logger.warning("No speaker turns available, using unknown speaker")
            return segments.map { segment in
                LabeledSegment(
                    speakerID: "S?",
                    text: segment.text,
                    start: segment.startTime,
                    end: segment.endTime
                )
            }
        }

        logger.info("Aligning \(segments.count) segments with \(turns.count) speaker turns")

        var labeled: [LabeledSegment] = []

        for segment in segments {
            let speakerID = assignSpeaker(
                to: segment,
                using: turns
            )

            labeled.append(LabeledSegment(
                speakerID: speakerID,
                text: segment.text,
                start: segment.startTime,
                end: segment.endTime
            ))
        }

        // Log speaker distribution
        let distribution = labeled.reduce(into: [String: Int]()) { counts, segment in
            counts[segment.speakerID, default: 0] += 1
        }
        logger.info("Speaker distribution in transcript: \(distribution)")

        return labeled
    }

    /// Assign speaker labels to SFTranscription segments
    ///
    /// Convenience method for working with Speech framework transcriptions.
    ///
    /// - Parameters:
    ///   - transcription: SFTranscription with segments
    ///   - turns: Array of speaker diarization turns
    /// - Returns: Array of labeled segments
    public static func label(
        transcription: SFTranscription,
        turns: [SpeakerTurn]
    ) -> [LabeledSegment] {
        let segments = transcription.segments.map { segment in
            TranscriptChunkData(
                meetingID: UUID(), // Dummy ID for alignment
                index: 0,
                text: segment.substring,
                startTime: segment.timestamp,
                endTime: segment.timestamp + segment.duration,
                isFinal: true
            )
        }

        return label(segments: segments, turns: turns)
    }

    // MARK: - Private Helpers

    /// Assign speaker to a single segment using maximum overlap strategy
    private static func assignSpeaker(
        to segment: TranscriptChunkData,
        using turns: [SpeakerTurn]
    ) -> String {
        let segmentStart = segment.startTime
        let segmentEnd = segment.endTime
        let segmentMid = (segmentStart + segmentEnd) / 2

        // Strategy 1: Find turn that contains segment midpoint
        if let turn = turns.first(where: { $0.contains(segmentMid) }) {
            return turn.speakerID
        }

        // Strategy 2: Find turn with maximum overlap
        var maxOverlap: TimeInterval = 0
        var bestSpeaker: String? = nil

        for turn in turns {
            let overlap = computeOverlap(
                segment: (segmentStart, segmentEnd),
                turn: (turn.start, turn.end)
            )

            if overlap > maxOverlap {
                maxOverlap = overlap
                bestSpeaker = turn.speakerID
            }
        }

        if let speaker = bestSpeaker, maxOverlap > 0 {
            return speaker
        }

        // Strategy 3: Find nearest turn by time
        if let nearestTurn = findNearestTurn(
            to: segmentMid,
            in: turns
        ) {
            return nearestTurn.speakerID
        }

        // Fallback: unknown speaker
        return "S?"
    }

    /// Compute temporal overlap between segment and turn
    private static func computeOverlap(
        segment: (start: TimeInterval, end: TimeInterval),
        turn: (start: TimeInterval, end: TimeInterval)
    ) -> TimeInterval {
        let overlapStart = max(segment.start, turn.start)
        let overlapEnd = min(segment.end, turn.end)

        return max(0, overlapEnd - overlapStart)
    }

    /// Find speaker turn nearest to a given timestamp
    private static func findNearestTurn(
        to time: TimeInterval,
        in turns: [SpeakerTurn]
    ) -> SpeakerTurn? {
        guard !turns.isEmpty else { return nil }

        var minDistance: TimeInterval = .infinity
        var nearestTurn: SpeakerTurn? = nil

        for turn in turns {
            let distance: TimeInterval

            if turn.contains(time) {
                distance = 0
            } else if time < turn.start {
                distance = turn.start - time
            } else {
                distance = time - turn.end
            }

            if distance < minDistance {
                minDistance = distance
                nearestTurn = turn
            }
        }

        return nearestTurn
    }

    // MARK: - Batch Alignment

    /// Apply speaker labels to existing transcript chunks
    ///
    /// Updates TranscriptChunkData objects with speaker IDs based on diarization turns.
    ///
    /// - Parameters:
    ///   - chunks: Array of transcript chunks to label
    ///   - turns: Array of speaker diarization turns
    /// - Returns: Array of updated chunks with speaker IDs (Note: speakerID not yet in model)
    public static func applyLabels(
        to chunks: [TranscriptChunkData],
        using turns: [SpeakerTurn]
    ) -> [(chunk: TranscriptChunkData, speakerID: String)] {
        let labeled = label(segments: chunks, turns: turns)

        return zip(chunks, labeled).map { chunk, segment in
            (chunk: chunk, speakerID: segment.speakerID)
        }
    }

    /// Format labeled segments for display
    ///
    /// - Parameter segments: Array of labeled segments
    /// - Returns: Formatted string with speaker tags
    public static func format(segments: [LabeledSegment]) -> String {
        segments.map { "\($0.speakerID): \($0.text)" }
            .joined(separator: "\n")
    }

    /// Group labeled segments by speaker
    ///
    /// - Parameter segments: Array of labeled segments
    /// - Returns: Dictionary mapping speaker IDs to their segments
    public static func groupBySpeaker(
        _ segments: [LabeledSegment]
    ) -> [String: [LabeledSegment]] {
        segments.reduce(into: [String: [LabeledSegment]]()) { result, segment in
            result[segment.speakerID, default: []].append(segment)
        }
    }

    /// Compute speaker statistics from labeled segments
    ///
    /// - Parameter segments: Array of labeled segments
    /// - Returns: Dictionary with speaker talk time and word count
    public static func computeStatistics(
        _ segments: [LabeledSegment]
    ) -> [String: (talkTime: TimeInterval, wordCount: Int)] {
        segments.reduce(into: [String: (TimeInterval, Int)]()) { result, segment in
            let current = result[segment.speakerID] ?? (0, 0)
            let wordCount = segment.text.split(separator: " ").count
            result[segment.speakerID] = (
                current.0 + segment.duration,
                current.1 + wordCount
            )
        }
    }
}
