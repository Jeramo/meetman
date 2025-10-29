//
//  Repositories.swift
//  MeetingCopilot
//
//  Repository pattern for domain entities
//

import Foundation
import SwiftData
import OSLog

private let logger = Logger(subsystem: "com.jeramo.meetingman", category: "persistence")

// MARK: - Meeting Repository

/// Repository for Meeting CRUD operations
public final class MeetingRepository: @unchecked Sendable {

    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    /// Create new meeting
    public func create(
        title: String,
        attendees: [PersonRef] = []
    ) throws -> Meeting {
        let meeting = Meeting(
            title: title,
            attendees: attendees
        )

        context.insert(meeting)
        try context.saveChanges()

        logger.info("Created meeting: \(meeting.id)")
        return meeting
    }

    /// Fetch meeting by ID
    public func fetch(id: UUID) throws -> Meeting? {
        let predicate = #Predicate<Meeting> { $0.id == id }
        return try context.fetch(Meeting.self, predicate: predicate).first
    }

    /// Fetch all meetings, optionally filtered
    public func fetchAll(
        activeOnly: Bool = false,
        sortBy: SortDescriptor<Meeting> = SortDescriptor(\.startedAt, order: .reverse)
    ) throws -> [Meeting] {
        let predicate: Predicate<Meeting>? = activeOnly ? #Predicate { $0.endedAt == nil } : nil
        return try context.fetch(Meeting.self, predicate: predicate, sortBy: [sortBy])
    }

    /// Search meetings by title
    public func search(query: String) throws -> [Meeting] {
        let predicate = #Predicate<Meeting> { meeting in
            meeting.title.localizedStandardContains(query)
        }
        return try context.fetch(Meeting.self, predicate: predicate, sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
    }

    /// Update meeting
    public func update(_ meeting: Meeting) throws {
        meeting.updatedAt = Date()
        try context.saveChanges()
        logger.debug("Updated meeting: \(meeting.id)")
    }

    /// End meeting
    public func endMeeting(_ meeting: Meeting) throws {
        meeting.endedAt = Date()
        meeting.updatedAt = Date()
        try context.saveChanges()
        logger.info("Ended meeting: \(meeting.id)")
    }

    /// Delete meeting
    public func delete(_ meeting: Meeting) throws {
        context.delete(meeting)
        try context.saveChanges()
        logger.info("Deleted meeting: \(meeting.id)")
    }

    /// Get active meeting (if any)
    public func getActiveMeeting() throws -> Meeting? {
        let predicate = #Predicate<Meeting> { $0.endedAt == nil }
        let meetings = try context.fetch(
            Meeting.self,
            predicate: predicate,
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return meetings.first
    }
}

// MARK: - Transcript Repository

/// Repository for TranscriptChunk operations
public final class TranscriptRepository: @unchecked Sendable {

    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    /// Add transcript chunk
    public func add(_ chunk: TranscriptChunk) throws {
        context.insert(chunk)
        try context.saveChanges()
        logger.debug("Added transcript chunk #\(chunk.index) for meeting \(chunk.meetingID)")
    }

    /// Add multiple chunks
    public func addBatch(_ chunks: [TranscriptChunk]) throws {
        for chunk in chunks {
            context.insert(chunk)
        }
        try context.saveChanges()
        logger.info("Added \(chunks.count) transcript chunks")
    }

    /// Fetch chunks for meeting
    public func fetchForMeeting(id: UUID) throws -> [TranscriptChunk] {
        let predicate = #Predicate<TranscriptChunk> { $0.meetingID == id }
        return try context.fetch(
            TranscriptChunk.self,
            predicate: predicate,
            sortBy: [SortDescriptor(\.index)]
        )
    }

    /// Get latest chunk for meeting
    public func getLatest(for meetingID: UUID) throws -> TranscriptChunk? {
        let predicate = #Predicate<TranscriptChunk> { $0.meetingID == meetingID }
        let chunks = try context.fetch(
            TranscriptChunk.self,
            predicate: predicate,
            sortBy: [SortDescriptor(\.index, order: .reverse)]
        )
        return chunks.first
    }
}

// MARK: - Decision Repository

/// Repository for Decision operations
public final class DecisionRepository: @unchecked Sendable {

    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    /// Add decision
    public func add(meetingID: UUID, text: String, owner: String? = nil) throws -> Decision {
        let decision = Decision(
            meetingID: meetingID,
            text: text,
            owner: owner
        )

        context.insert(decision)
        try context.saveChanges()

        logger.info("Added decision for meeting \(meetingID)")
        return decision
    }

    /// Fetch decisions for meeting
    public func fetchForMeeting(id: UUID) throws -> [Decision] {
        let predicate = #Predicate<Decision> { $0.meetingID == id }
        return try context.fetch(
            Decision.self,
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp)]
        )
    }

    /// Update decision
    public func update(_ decision: Decision) throws {
        try context.saveChanges()
        logger.debug("Updated decision: \(decision.id)")
    }

    /// Delete decision
    public func delete(_ decision: Decision) throws {
        context.delete(decision)
        try context.saveChanges()
        logger.info("Deleted decision: \(decision.id)")
    }
}

// MARK: - Convenience Factory

/// Factory for creating repositories with shared context
public struct RepositoryFactory {

    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public var meetings: MeetingRepository {
        MeetingRepository(context: context)
    }

    public var transcripts: TranscriptRepository {
        TranscriptRepository(context: context)
    }

    public var decisions: DecisionRepository {
        DecisionRepository(context: context)
    }
}
