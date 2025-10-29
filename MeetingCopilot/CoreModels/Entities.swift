//
//  Entities.swift
//  MeetingCopilot
//
//  SwiftData models for meeting data
//

import Foundation
import SwiftData

// MARK: - Meeting

@Model
public final class Meeting {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var startedAt: Date
    public var endedAt: Date?
    public var attendees: [PersonRef]
    public var audioURL: URL?
    @Relationship(deleteRule: .cascade) public var transcriptChunks: [TranscriptChunk]
    @Relationship(deleteRule: .cascade) public var decisions: [Decision]
    public var summaryJSON: String? // Canonical JSON from NLP
    public var polishedTranscript: String? // AI-polished version for display (iOS 26+)
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        attendees: [PersonRef] = [],
        audioURL: URL? = nil,
        transcriptChunks: [TranscriptChunk] = [],
        decisions: [Decision] = [],
        summaryJSON: String? = nil,
        polishedTranscript: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.attendees = attendees
        self.audioURL = audioURL
        self.transcriptChunks = transcriptChunks
        self.decisions = decisions
        self.summaryJSON = summaryJSON
        self.polishedTranscript = polishedTranscript
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Full transcript text concatenated
    public var fullTranscript: String {
        transcriptChunks
            .sorted { $0.index < $1.index }
            .map(\.text)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: " ")
    }

    /// Duration in seconds
    public var duration: TimeInterval? {
        guard let endedAt = endedAt else { return nil }
        return endedAt.timeIntervalSince(startedAt)
    }

    /// Whether meeting is currently active
    public var isActive: Bool {
        endedAt == nil
    }
}

// MARK: - TranscriptChunk

@Model
public final class TranscriptChunk {
    @Attribute(.unique) public var id: UUID
    public var meetingID: UUID
    public var index: Int
    public var text: String
    public var startTime: TimeInterval
    public var endTime: TimeInterval
    public var isFinal: Bool
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        meetingID: UUID,
        index: Int,
        text: String,
        startTime: TimeInterval,
        endTime: TimeInterval,
        isFinal: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.meetingID = meetingID
        self.index = index
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.isFinal = isFinal
        self.createdAt = createdAt
    }
}

// MARK: - Decision

@Model
public final class Decision {
    @Attribute(.unique) public var id: UUID
    public var meetingID: UUID
    public var text: String
    public var owner: String?
    public var timestamp: Date
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        meetingID: UUID,
        text: String,
        owner: String? = nil,
        timestamp: Date = Date(),
        createdAt: Date = Date()
    ) {
        self.id = id
        self.meetingID = meetingID
        self.text = text
        self.owner = owner
        self.timestamp = timestamp
        self.createdAt = createdAt
    }
}

// MARK: - Value Types

/// Reference to a task/action item
public struct TaskRef: Codable, Hashable, Sendable {
    public let title: String
    public let owner: String?
    public let due: Date?
    public var reminderID: String?

    public init(title: String, owner: String? = nil, due: Date? = nil, reminderID: String? = nil) {
        self.title = title
        self.owner = owner
        self.due = due
        self.reminderID = reminderID
    }
}

/// Reference to a person/attendee
public struct PersonRef: Codable, Hashable, Sendable {
    public let name: String
    public let email: String?

    public init(name: String, email: String? = nil) {
        self.name = name
        self.email = email
    }
}

/// Sendable DTO for transcript chunk data
public struct TranscriptChunkData: Sendable {
    public let id: UUID
    public let meetingID: UUID
    public let index: Int
    public let text: String
    public let startTime: TimeInterval
    public let endTime: TimeInterval
    public let isFinal: Bool

    public init(id: UUID = UUID(), meetingID: UUID, index: Int, text: String, startTime: TimeInterval, endTime: TimeInterval, isFinal: Bool) {
        self.id = id
        self.meetingID = meetingID
        self.index = index
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.isFinal = isFinal
    }

    /// Convert to SwiftData model
    public func toModel() -> TranscriptChunk {
        TranscriptChunk(id: id, meetingID: meetingID, index: index, text: text, startTime: startTime, endTime: endTime, isFinal: isFinal)
    }
}

extension TranscriptChunk {
    /// Convert to Sendable DTO
    public func toData() -> TranscriptChunkData {
        TranscriptChunkData(id: id, meetingID: meetingID, index: index, text: text, startTime: startTime, endTime: endTime, isFinal: isFinal)
    }
}
