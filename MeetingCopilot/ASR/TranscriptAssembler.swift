//
//  TranscriptAssembler.swift
//  MeetingCopilot
//
//  Coalesces and deduplicates transcript chunks
//

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.jeramo.meetingman", category: "asr")

/// Assembles and deduplicates streaming transcript chunks
public actor TranscriptAssembler {

    private var chunks: [TranscriptChunkData] = []
    private var pendingChunk: TranscriptChunkData?
    private let debounceInterval: TimeInterval

    /// Initialize with debounce interval for partial results
    public init(debounceInterval: TimeInterval = 0.5) {
        self.debounceInterval = debounceInterval
    }

    /// Add a new chunk, handling partials and duplicates
    public func append(_ chunk: TranscriptChunkData) {
        if chunk.isFinal {
            // Final chunk - commit it
            chunks.append(chunk)
            pendingChunk = nil
            logger.debug("Committed final chunk #\(chunk.index)")
        } else {
            // Partial chunk - hold for debounce
            pendingChunk = chunk
            logger.debug("Holding partial chunk #\(chunk.index)")
        }
    }

    /// Flush pending chunk as final
    public func flush() {
        if let pending = pendingChunk {
            let finalChunk = TranscriptChunkData(
                id: pending.id,
                meetingID: pending.meetingID,
                index: pending.index,
                text: pending.text,
                startTime: pending.startTime,
                endTime: pending.endTime,
                isFinal: true
            )
            chunks.append(finalChunk)
            pendingChunk = nil
            logger.debug("Flushed pending chunk #\(finalChunk.index)")
        }
    }

    /// Get all committed chunks sorted by index
    public func getChunks() -> [TranscriptChunkData] {
        chunks.sorted { $0.index < $1.index }
    }

    /// Get full transcript text
    public func getFullTranscript() -> String {
        chunks
            .sorted { $0.index < $1.index }
            .map(\.text)
            .joined(separator: " ")
    }

    /// Get chunks since a specific index
    public func getChunksSince(index: Int) -> [TranscriptChunkData] {
        chunks
            .filter { $0.index > index }
            .sorted { $0.index < $1.index }
    }

    /// Clear all chunks
    public func reset() {
        chunks.removeAll()
        pendingChunk = nil
        logger.info("Reset assembler")
    }

    /// Merge overlapping or duplicate chunks
    public func deduplicate() {
        var seen = Set<String>()
        chunks = chunks.filter { chunk in
            let normalized = chunk.text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if seen.contains(normalized) {
                logger.debug("Removing duplicate chunk: \(normalized.prefix(50))")
                return false
            }
            seen.insert(normalized)
            return true
        }
    }

    /// Get statistics
    public func getStats() -> (chunkCount: Int, totalLength: Int, duration: TimeInterval?) {
        let chunkCount = chunks.count
        let totalLength = chunks.reduce(0) { $0 + $1.text.count }
        let duration = chunks.last.map { $0.endTime }

        return (chunkCount, totalLength, duration)
    }
}
