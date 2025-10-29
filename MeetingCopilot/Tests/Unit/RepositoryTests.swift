//
//  RepositoryTests.swift
//  MeetingCopilot
//
//  Unit tests for SwiftData repositories
//

import XCTest
import SwiftData
@testable import MeetingCopilot

final class RepositoryTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext!
    var meetingRepo: MeetingRepository!
    var transcriptRepo: TranscriptRepository!
    var decisionRepo: DecisionRepository!

    override func setUp() async throws {
        try await super.setUp()

        // Create in-memory container for testing
        let schema = Schema([Meeting.self, TranscriptChunk.self, Decision.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)

        meetingRepo = MeetingRepository(context: context)
        transcriptRepo = TranscriptRepository(context: context)
        decisionRepo = DecisionRepository(context: context)
    }

    override func tearDown() async throws {
        container = nil
        context = nil
        meetingRepo = nil
        transcriptRepo = nil
        decisionRepo = nil
        try await super.tearDown()
    }

    // MARK: - Meeting Repository Tests

    func testCreateMeeting() throws {
        let meeting = try meetingRepo.create(title: "Test Meeting")

        XCTAssertEqual(meeting.title, "Test Meeting")
        XCTAssertNil(meeting.endedAt)
        XCTAssertTrue(meeting.isActive)
    }

    func testCreateMeetingWithAttendees() throws {
        let attendees = [
            PersonRef(name: "Alice", email: "alice@example.com"),
            PersonRef(name: "Bob")
        ]

        let meeting = try meetingRepo.create(title: "Team Meeting", attendees: attendees)

        XCTAssertEqual(meeting.attendees.count, 2)
        XCTAssertEqual(meeting.attendees[0].name, "Alice")
    }

    func testFetchMeetingByID() throws {
        let created = try meetingRepo.create(title: "Test Meeting")

        let fetched = try meetingRepo.fetch(id: created.id)

        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.id, created.id)
        XCTAssertEqual(fetched?.title, "Test Meeting")
    }

    func testFetchAllMeetings() throws {
        _ = try meetingRepo.create(title: "Meeting 1")
        _ = try meetingRepo.create(title: "Meeting 2")
        _ = try meetingRepo.create(title: "Meeting 3")

        let all = try meetingRepo.fetchAll()

        XCTAssertEqual(all.count, 3)
    }

    func testFetchActiveMeetingsOnly() throws {
        let active = try meetingRepo.create(title: "Active Meeting")
        let ended = try meetingRepo.create(title: "Ended Meeting")
        try meetingRepo.endMeeting(ended)

        let activeMeetings = try meetingRepo.fetchAll(activeOnly: true)

        XCTAssertEqual(activeMeetings.count, 1)
        XCTAssertEqual(activeMeetings.first?.id, active.id)
    }

    func testSearchMeetings() throws {
        _ = try meetingRepo.create(title: "Project Alpha Meeting")
        _ = try meetingRepo.create(title: "Team Standup")
        _ = try meetingRepo.create(title: "Project Beta Review")

        let results = try meetingRepo.search(query: "Project")

        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.allSatisfy { $0.title.contains("Project") })
    }

    func testUpdateMeeting() throws {
        let meeting = try meetingRepo.create(title: "Original Title")

        meeting.title = "Updated Title"
        try meetingRepo.update(meeting)

        let fetched = try meetingRepo.fetch(id: meeting.id)
        XCTAssertEqual(fetched?.title, "Updated Title")
    }

    func testEndMeeting() throws {
        let meeting = try meetingRepo.create(title: "Test Meeting")
        XCTAssertNil(meeting.endedAt)

        try meetingRepo.endMeeting(meeting)

        XCTAssertNotNil(meeting.endedAt)
        XCTAssertFalse(meeting.isActive)
    }

    func testDeleteMeeting() throws {
        let meeting = try meetingRepo.create(title: "To Delete")

        try meetingRepo.delete(meeting)

        let fetched = try meetingRepo.fetch(id: meeting.id)
        XCTAssertNil(fetched)
    }

    func testGetActiveMeeting() throws {
        _ = try meetingRepo.create(title: "Ended 1")
        let active = try meetingRepo.create(title: "Active Meeting")
        _ = try meetingRepo.create(title: "Ended 2")

        // End the first and last
        let all = try meetingRepo.fetchAll()
        try meetingRepo.endMeeting(all[0])
        try meetingRepo.endMeeting(all[2])

        let activeMeeting = try meetingRepo.getActiveMeeting()

        XCTAssertNotNil(activeMeeting)
        XCTAssertEqual(activeMeeting?.id, active.id)
    }

    // MARK: - Transcript Repository Tests

    func testAddTranscriptChunk() throws {
        let meeting = try meetingRepo.create(title: "Test Meeting")

        let chunk = TranscriptChunk(
            meetingID: meeting.id,
            index: 0,
            text: "Hello world",
            startTime: 0,
            endTime: 1
        )

        try transcriptRepo.add(chunk)

        let chunks = try transcriptRepo.fetchForMeeting(id: meeting.id)
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks.first?.text, "Hello world")
    }

    func testAddBatchTranscripts() throws {
        let meeting = try meetingRepo.create(title: "Test Meeting")

        let chunks = [
            TranscriptChunk(meetingID: meeting.id, index: 0, text: "One", startTime: 0, endTime: 1),
            TranscriptChunk(meetingID: meeting.id, index: 1, text: "Two", startTime: 1, endTime: 2),
            TranscriptChunk(meetingID: meeting.id, index: 2, text: "Three", startTime: 2, endTime: 3)
        ]

        try transcriptRepo.addBatch(chunks)

        let fetched = try transcriptRepo.fetchForMeeting(id: meeting.id)
        XCTAssertEqual(fetched.count, 3)
    }

    func testFetchTranscriptsSorted() throws {
        let meeting = try meetingRepo.create(title: "Test Meeting")

        // Add in random order
        let chunk2 = TranscriptChunk(meetingID: meeting.id, index: 2, text: "Third", startTime: 2, endTime: 3)
        let chunk0 = TranscriptChunk(meetingID: meeting.id, index: 0, text: "First", startTime: 0, endTime: 1)
        let chunk1 = TranscriptChunk(meetingID: meeting.id, index: 1, text: "Second", startTime: 1, endTime: 2)

        try transcriptRepo.add(chunk2)
        try transcriptRepo.add(chunk0)
        try transcriptRepo.add(chunk1)

        let fetched = try transcriptRepo.fetchForMeeting(id: meeting.id)

        XCTAssertEqual(fetched[0].text, "First")
        XCTAssertEqual(fetched[1].text, "Second")
        XCTAssertEqual(fetched[2].text, "Third")
    }

    func testGetLatestTranscript() throws {
        let meeting = try meetingRepo.create(title: "Test Meeting")

        let chunks = [
            TranscriptChunk(meetingID: meeting.id, index: 0, text: "One", startTime: 0, endTime: 1),
            TranscriptChunk(meetingID: meeting.id, index: 1, text: "Two", startTime: 1, endTime: 2),
            TranscriptChunk(meetingID: meeting.id, index: 2, text: "Latest", startTime: 2, endTime: 3)
        ]

        try transcriptRepo.addBatch(chunks)

        let latest = try transcriptRepo.getLatest(for: meeting.id)

        XCTAssertNotNil(latest)
        XCTAssertEqual(latest?.text, "Latest")
        XCTAssertEqual(latest?.index, 2)
    }

    // MARK: - Decision Repository Tests

    func testAddDecision() throws {
        let meeting = try meetingRepo.create(title: "Test Meeting")

        let decision = try decisionRepo.add(
            meetingID: meeting.id,
            text: "Decided to proceed",
            owner: "Alice"
        )

        XCTAssertEqual(decision.text, "Decided to proceed")
        XCTAssertEqual(decision.owner, "Alice")
    }

    func testFetchDecisionsForMeeting() throws {
        let meeting = try meetingRepo.create(title: "Test Meeting")

        _ = try decisionRepo.add(meetingID: meeting.id, text: "Decision 1")
        _ = try decisionRepo.add(meetingID: meeting.id, text: "Decision 2")

        let decisions = try decisionRepo.fetchForMeeting(id: meeting.id)

        XCTAssertEqual(decisions.count, 2)
    }

    func testUpdateDecision() throws {
        let meeting = try meetingRepo.create(title: "Test Meeting")
        let decision = try decisionRepo.add(meetingID: meeting.id, text: "Original")

        decision.text = "Updated"
        try decisionRepo.update(decision)

        let decisions = try decisionRepo.fetchForMeeting(id: meeting.id)
        XCTAssertEqual(decisions.first?.text, "Updated")
    }

    func testDeleteDecision() throws {
        let meeting = try meetingRepo.create(title: "Test Meeting")
        let decision = try decisionRepo.add(meetingID: meeting.id, text: "To Delete")

        try decisionRepo.delete(decision)

        let decisions = try decisionRepo.fetchForMeeting(id: meeting.id)
        XCTAssertTrue(decisions.isEmpty)
    }

    // MARK: - Cascade Delete Tests

    func testCascadeDeleteTranscripts() throws {
        let meeting = try meetingRepo.create(title: "Test Meeting")

        let chunk = TranscriptChunk(meetingID: meeting.id, index: 0, text: "Test", startTime: 0, endTime: 1)
        try transcriptRepo.add(chunk)

        // Delete meeting should cascade to transcripts
        try meetingRepo.delete(meeting)

        let transcripts = try transcriptRepo.fetchForMeeting(id: meeting.id)
        XCTAssertTrue(transcripts.isEmpty, "Transcripts should be deleted with meeting")
    }
}
