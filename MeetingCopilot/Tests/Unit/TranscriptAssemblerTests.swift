//
//  TranscriptAssemblerTests.swift
//  MeetingCopilot
//
//  Unit tests for TranscriptAssembler
//

import XCTest
@testable import MeetingCopilot

final class TranscriptAssemblerTests: XCTestCase {

    var assembler: TranscriptAssembler!
    let testMeetingID = UUID()

    override func setUp() async throws {
        try await super.setUp()
        assembler = TranscriptAssembler()
    }

    override func tearDown() async throws {
        assembler = nil
        try await super.tearDown()
    }

    // MARK: - Basic Operations

    func testAppendFinalChunk() async {
        let chunk = TranscriptChunkData(
            meetingID: testMeetingID,
            index: 0,
            text: "Hello world",
            startTime: 0,
            endTime: 1,
            isFinal: true
        )

        await assembler.append(chunk)
        let chunks = await assembler.getChunks()

        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks.first?.text, "Hello world")
    }

    func testAppendPartialChunk() async {
        let chunk = TranscriptChunkData(
            meetingID: testMeetingID,
            index: 0,
            text: "Hello",
            startTime: 0,
            endTime: 1,
            isFinal: false
        )

        await assembler.append(chunk)
        let chunks = await assembler.getChunks()

        // Partial chunks are not committed until flushed
        XCTAssertEqual(chunks.count, 0)
    }

    func testFlushPendingChunk() async {
        let chunk = TranscriptChunkData(
            meetingID: testMeetingID,
            index: 0,
            text: "Hello",
            startTime: 0,
            endTime: 1,
            isFinal: false
        )

        await assembler.append(chunk)
        await assembler.flush()

        let chunks = await assembler.getChunks()
        XCTAssertEqual(chunks.count, 1)
        XCTAssertTrue(chunks.first!.isFinal, "Flushed chunk should be marked as final")
    }

    func testGetFullTranscript() async {
        let chunks = [
            TranscriptChunkData(meetingID: testMeetingID, index: 0, text: "Hello", startTime: 0, endTime: 1, isFinal: true),
            TranscriptChunkData(meetingID: testMeetingID, index: 1, text: "world", startTime: 1, endTime: 2, isFinal: true),
            TranscriptChunkData(meetingID: testMeetingID, index: 2, text: "test", startTime: 2, endTime: 3, isFinal: true)
        ]

        for chunk in chunks {
            await assembler.append(chunk)
        }

        let fullText = await assembler.getFullTranscript()
        XCTAssertEqual(fullText, "Hello world test")
    }

    // MARK: - Ordering

    func testChunkOrdering() async {
        // Add chunks out of order
        let chunk2 = TranscriptChunkData(meetingID: testMeetingID, index: 2, text: "third", startTime: 2, endTime: 3, isFinal: true)
        let chunk0 = TranscriptChunkData(meetingID: testMeetingID, index: 0, text: "first", startTime: 0, endTime: 1, isFinal: true)
        let chunk1 = TranscriptChunkData(meetingID: testMeetingID, index: 1, text: "second", startTime: 1, endTime: 2, isFinal: true)

        await assembler.append(chunk2)
        await assembler.append(chunk0)
        await assembler.append(chunk1)

        let fullText = await assembler.getFullTranscript()
        XCTAssertEqual(fullText, "first second third", "Should order by index")
    }

    func testGetChunksSince() async {
        let chunks = [
            TranscriptChunkData(meetingID: testMeetingID, index: 0, text: "A", startTime: 0, endTime: 1, isFinal: true),
            TranscriptChunkData(meetingID: testMeetingID, index: 1, text: "B", startTime: 1, endTime: 2, isFinal: true),
            TranscriptChunkData(meetingID: testMeetingID, index: 2, text: "C", startTime: 2, endTime: 3, isFinal: true),
            TranscriptChunkData(meetingID: testMeetingID, index: 3, text: "D", startTime: 3, endTime: 4, isFinal: true)
        ]

        for chunk in chunks {
            await assembler.append(chunk)
        }

        let newChunks = await assembler.getChunksSince(index: 1)
        XCTAssertEqual(newChunks.count, 2, "Should return chunks after index 1")
        XCTAssertEqual(newChunks.first?.text, "C")
        XCTAssertEqual(newChunks.last?.text, "D")
    }

    // MARK: - Deduplication

    func testDeduplication() async {
        let chunk1 = TranscriptChunkData(meetingID: testMeetingID, index: 0, text: "Hello world", startTime: 0, endTime: 1, isFinal: true)
        let chunk2 = TranscriptChunkData(meetingID: testMeetingID, index: 1, text: "hello world", startTime: 1, endTime: 2, isFinal: true) // Duplicate (case-insensitive)
        let chunk3 = TranscriptChunkData(meetingID: testMeetingID, index: 2, text: "Goodbye", startTime: 2, endTime: 3, isFinal: true)

        await assembler.append(chunk1)
        await assembler.append(chunk2)
        await assembler.append(chunk3)

        await assembler.deduplicate()

        let chunks = await assembler.getChunks()
        XCTAssertEqual(chunks.count, 2, "Should remove duplicate")
    }

    // MARK: - Statistics

    func testGetStats() async {
        let chunks = [
            TranscriptChunkData(meetingID: testMeetingID, index: 0, text: "Hello", startTime: 0, endTime: 1, isFinal: true),
            TranscriptChunkData(meetingID: testMeetingID, index: 1, text: "world", startTime: 1, endTime: 2.5, isFinal: true)
        ]

        for chunk in chunks {
            await assembler.append(chunk)
        }

        let stats = await assembler.getStats()

        XCTAssertEqual(stats.chunkCount, 2)
        XCTAssertEqual(stats.totalLength, 10) // "Hello" + "world" = 10 chars
        XCTAssertEqual(stats.duration, 2.5)
    }

    func testEmptyStats() async {
        let stats = await assembler.getStats()

        XCTAssertEqual(stats.chunkCount, 0)
        XCTAssertEqual(stats.totalLength, 0)
        XCTAssertNil(stats.duration)
    }

    // MARK: - Reset

    func testReset() async {
        let chunk = TranscriptChunkData(meetingID: testMeetingID, index: 0, text: "Hello", startTime: 0, endTime: 1, isFinal: true)
        await assembler.append(chunk)

        var chunks = await assembler.getChunks()
        XCTAssertEqual(chunks.count, 1)

        await assembler.reset()

        chunks = await assembler.getChunks()
        XCTAssertEqual(chunks.count, 0, "Should clear all chunks")
    }
}
