//
//  ReviewVM.swift
//  MeetingCopilot
//
//  ViewModel for meeting review and summary
//

import Foundation
import SwiftUI
@preconcurrency import SwiftData
import Observation
import OSLog

private let logger = Logger(subsystem: "com.jeramo.meetingman", category: "ui")

/// Observable view model for meeting review
@MainActor
@Observable
public final class ReviewVM {

    // MARK: - State

    public var meeting: Meeting?
    public var summary: SummaryResult?
    public var isGeneratingSummary = false
    public var isCreatingReminders = false
    public var errorMessage: String?
    public var successMessage: String?

    // MARK: - Dependencies

    @ObservationIgnored private let nlpService = NLPService()
    @ObservationIgnored private let taskCreator = TaskCreator()

    // Computed repositories
    private var context: ModelContext {
        Store.shared.mainContext
    }

    private var meetingRepo: MeetingRepository {
        MeetingRepository(context: context)
    }

    // MARK: - Initialization

    public init(meeting: Meeting? = nil) {
        self.meeting = meeting
        loadSummary()
    }

    // MARK: - Actions

    /// Load meeting by ID
    public func loadMeeting(id: UUID) {
        do {
            meeting = try meetingRepo.fetch(id: id)
            loadSummary()
        } catch {
            logger.error("Failed to load meeting: \(error.localizedDescription)")
            errorMessage = "Failed to load meeting"
        }
    }

    /// Load existing summary from meeting
    private func loadSummary() {
        guard let meeting = meeting,
              let summaryJSON = meeting.summaryJSON,
              let data = summaryJSON.data(using: .utf8) else {
            return
        }

        do {
            summary = try JSONDecoder().decode(SummaryResult.self, from: data)
            logger.debug("Loaded existing summary")
        } catch {
            logger.error("Failed to decode summary: \(error.localizedDescription)")
        }
    }

    /// Generate summary from transcript
    public func generateSummary() async {
        guard let meeting = meeting else { return }

        isGeneratingSummary = true
        errorMessage = nil

        do {
            logger.info("Generating summary for meeting \(meeting.id)")

            // Extract text on MainActor before async call
            let transcript = meeting.transcriptChunks
                .sorted { $0.index < $1.index }
                .map(\.text)
                .joined(separator: " ")

            summary = try await nlpService.summarize(transcript: transcript)

            // Save to meeting
            let encoder = JSONEncoder()
            meeting.summaryJSON = String(data: try encoder.encode(summary), encoding: .utf8)
            try meetingRepo.update(meeting)

            successMessage = "Summary generated successfully"
            logger.info("Summary generated")
        } catch {
            logger.error("Failed to generate summary: \(error.localizedDescription)")
            errorMessage = "Failed to generate summary: \(error.localizedDescription)"
        }

        isGeneratingSummary = false
    }

    /// Refine summary with latest chunks
    public func refineWithLatestChunk(_ chunk: TranscriptChunk) async {
        guard let currentSummary = summary else { return }

        do {
            // Extract text on MainActor before async call
            let newText = chunk.text
            summary = try await nlpService.refine(context: currentSummary, newText: newText)
        } catch {
            logger.error("Failed to refine summary: \(error.localizedDescription)")
        }
    }

    /// Create reminders from action items
    public func pushActionItemsToReminders() async throws -> [String] {
        guard let meeting = meeting, let summary = summary else {
            throw ActionsError.noDefaultReminderList
        }

        guard !summary.actionItems.isEmpty else {
            return []
        }

        isCreatingReminders = true
        errorMessage = nil

        do {
            logger.info("Creating \(summary.actionItems.count) reminders")

            let reminderIDs = try await taskCreator.createReminders(
                from: summary.actionItems,
                meetingTitle: meeting.title
            )

            successMessage = "Created \(reminderIDs.count) reminders"
            logger.info("Created reminders")

            isCreatingReminders = false
            return reminderIDs
        } catch {
            logger.error("Failed to create reminders: \(error.localizedDescription)")
            errorMessage = "Failed to create reminders: \(error.localizedDescription)"
            isCreatingReminders = false
            throw error
        }
    }

    /// Export as Markdown
    public func exportMarkdown() throws -> URL {
        guard let meeting = meeting else {
            throw ExportError.invalidFormat
        }

        let tempDir = FileManager.default.temporaryDirectory
        return try MarkdownExporter.export(meeting: meeting, summary: summary, to: tempDir)
    }

    /// Export as JSON
    public func exportJSON() throws -> URL {
        guard let meeting = meeting else {
            throw ExportError.invalidFormat
        }

        let tempDir = FileManager.default.temporaryDirectory
        return try JSONExporter.export(meeting: meeting, summary: summary, to: tempDir)
    }

    /// Clear messages
    public func clearMessages() {
        errorMessage = nil
        successMessage = nil
    }
}
