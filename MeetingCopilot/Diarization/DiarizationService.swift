//
//  DiarizationService.swift
//  MeetingCopilot
//
//  High-level service for speaker diarization integration
//

import AVFoundation
import Foundation
import OSLog
import SwiftData

private let logger = Logger(subsystem: "com.jeramo.meetingman", category: "diarization")

/// Service for performing and managing speaker diarization
public final class DiarizationService: @unchecked Sendable {

    private let diarizer: Diarizer
    private let context: ModelContext

    /// Initialize with optional Core ML model URL
    /// - Parameters:
    ///   - embedderURL: URL to compiled .mlmodelc model (nil for heuristic fallback)
    ///   - context: SwiftData model context for database updates
    public init(embedderURL: URL? = nil, context: ModelContext) {
        self.diarizer = Diarizer(embedderURL: embedderURL)
        self.context = context
    }

    /// Perform diarization on a meeting's audio and update transcript chunks
    ///
    /// This is the main entry point for post-recording diarization.
    /// Loads audio from file, runs diarization, aligns with transcript chunks,
    /// and updates the database.
    ///
    /// - Parameters:
    ///   - meeting: Meeting to diarize
    ///   - progressHandler: Optional callback for progress updates (0.0 to 1.0)
    /// - Returns: Array of speaker turns
    @discardableResult
    public func diarize(
        meeting: Meeting,
        progressHandler: (@Sendable (Double, String) -> Void)? = nil
    ) async throws -> [SpeakerTurn] {
        logger.info("Starting diarization for meeting \(meeting.id)")

        guard let audioURL = meeting.audioURL else {
            throw DiarizationError.noAudioFile
        }

        // Step 1: Load audio (20% progress)
        progressHandler?(0.0, "Loading audio file...")
        let (pcm, sampleRate) = try loadWAVFile(url: audioURL)
        progressHandler?(0.2, "Audio loaded")

        logger.info("Loaded audio: \(pcm.count) samples at \(sampleRate)Hz")

        // Step 2: Run diarization (60% progress)
        progressHandler?(0.2, "Detecting speakers...")
        let turns = diarizer.diarize(pcm: pcm, sampleRate: sampleRate)
        progressHandler?(0.8, "Speaker detection complete")

        logger.info("Diarization complete: \(turns.count) speaker turns")

        guard !turns.isEmpty else {
            logger.warning("No speaker turns detected")
            return []
        }

        // Step 3: Align with transcript chunks (10% progress)
        progressHandler?(0.8, "Aligning with transcript...")
        try updateTranscriptChunks(for: meeting, with: turns)
        progressHandler?(0.9, "Transcript updated")

        // Step 4: Save to database
        progressHandler?(0.9, "Saving...")
        try context.saveChanges()
        progressHandler?(1.0, "Diarization complete")

        logger.info("Diarization service complete for meeting \(meeting.id)")

        return turns
    }

    /// Update transcript chunks with speaker labels
    private func updateTranscriptChunks(
        for meeting: Meeting,
        with turns: [SpeakerTurn]
    ) throws {
        let chunks = meeting.transcriptChunks.sorted { $0.index < $1.index }

        guard !chunks.isEmpty else {
            logger.warning("No transcript chunks to update")
            return
        }

        // Convert chunks to data format for alignment
        let chunkData = chunks.map { $0.toData() }

        // Perform alignment
        let labeled = Alignment.label(segments: chunkData, turns: turns)

        // Update chunks with speaker labels
        for (chunk, labeledSegment) in zip(chunks, labeled) {
            chunk.speakerID = labeledSegment.speakerID
        }

        logger.info("Updated \(chunks.count) transcript chunks with speaker labels")
    }

    /// Generate speaker statistics for a meeting
    public func generateStatistics(for meeting: Meeting) -> SpeakerStatistics? {
        let chunks = meeting.transcriptChunks.sorted { $0.index < $1.index }

        // Convert to labeled segments
        let segments = chunks.compactMap { chunk -> LabeledSegment? in
            guard let speakerID = chunk.speakerID else { return nil }
            return LabeledSegment(
                speakerID: speakerID,
                text: chunk.text,
                start: chunk.startTime,
                end: chunk.endTime
            )
        }

        guard !segments.isEmpty else { return nil }

        let stats = Alignment.computeStatistics(segments)
        let totalDuration = meeting.duration ?? 0

        return SpeakerStatistics(
            speakers: stats.mapValues { SpeakerStats(talkTime: $0.talkTime, wordCount: $0.wordCount) },
            totalDuration: totalDuration
        )
    }

    // MARK: - WAV File Loading

    /// Load WAV file and convert to Float PCM
    ///
    /// - Parameter url: URL to WAV file
    /// - Returns: Tuple of (PCM samples, sample rate)
    private func loadWAVFile(url: URL) throws -> ([Float], Double) {
        // Open audio file
        guard let audioFile = try? AVAudioFile(forReading: url) else {
            throw DiarizationError.audioLoadFailed
        }

        let format = audioFile.processingFormat
        let frameCount = AVAudioFrameCount(audioFile.length)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw DiarizationError.audioLoadFailed
        }

        try audioFile.read(into: buffer)

        // Convert to Float array
        let pcm = convertToFloatPCM(buffer)

        logger.debug("Loaded WAV: \(pcm.count) samples, \(format.sampleRate)Hz, \(format.channelCount)ch")

        return (pcm, format.sampleRate)
    }

    /// Convert AVAudioPCMBuffer to Float array
    private func convertToFloatPCM(_ buffer: AVAudioPCMBuffer) -> [Float] {
        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)

        guard let channelData = buffer.floatChannelData else {
            return []
        }

        var result = [Float]()
        result.reserveCapacity(frameLength)

        if channelCount == 1 {
            // Mono: direct copy
            let channel = channelData[0]
            for i in 0..<frameLength {
                result.append(channel[i])
            }
        } else {
            // Multi-channel: average to mono
            for i in 0..<frameLength {
                var sum: Float = 0
                for ch in 0..<channelCount {
                    sum += channelData[ch][i]
                }
                result.append(sum / Float(channelCount))
            }
        }

        return result
    }
}

// MARK: - Speaker Statistics

/// Speaker participation statistics
public struct SpeakerStatistics: Sendable {
    public let speakers: [String: SpeakerStats]
    public let totalDuration: TimeInterval

    /// Format as human-readable string
    public func formatted() -> String {
        let sortedSpeakers = speakers.keys.sorted()
        var lines: [String] = ["Speaker Statistics:"]

        for speakerID in sortedSpeakers {
            guard let stats = speakers[speakerID] else { continue }

            let percentage = totalDuration > 0 ? (stats.talkTime / totalDuration) * 100 : 0
            let minutes = Int(stats.talkTime / 60)
            let seconds = Int(stats.talkTime.truncatingRemainder(dividingBy: 60))

            lines.append("""
            \(speakerID): \(minutes)m \(seconds)s (\(String(format: "%.1f", percentage))%), \(stats.wordCount) words
            """)
        }

        return lines.joined(separator: "\n")
    }
}

public struct SpeakerStats: Sendable {
    public let talkTime: TimeInterval
    public let wordCount: Int
}

// MARK: - Extended Errors

extension DiarizationError {
    static var noAudioFile: DiarizationError {
        .audioLoadFailed
    }

    static var audioLoadFailed: DiarizationError {
        .invalidAudioRange // Reuse existing case
    }
}
