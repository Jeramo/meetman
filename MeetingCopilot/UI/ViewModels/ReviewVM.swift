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
    public var isPolishingText = false
    public var errorMessage: String?
    public var successMessage: String?

    /// Chosen output locale for summary generation (e.g., "en-us" fallback for unsupported languages)
    public var chosenOutputLocale: String?

    /// Polished transcript (if user requested beautification)
    public var polishedTranscript: String?
    /// Edit trail from polishing
    public var transcriptEdits: [PolishedText.Edit] = []

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

            // Check for preferred output locale from user choice during capture
            let preferredLocale = chosenOutputLocale ?? UserDefaults.standard.string(forKey: "preferred.output.locale")

            // Use standard summarization with built-in retry logic
            // Pass chosen output locale if user selected fallback
            summary = try await nlpService.summarize(transcript: transcript, forceOutputLocale: preferredLocale)

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

        // Re-fetch meeting to ensure relationships are loaded
        guard let freshMeeting = try meetingRepo.fetch(id: meeting.id) else {
            logger.error("Failed to fetch meeting for export: \(meeting.id)")
            throw ExportError.invalidFormat
        }

        logger.debug("Exporting Markdown: \(freshMeeting.transcriptChunks.count) transcript chunks, \(freshMeeting.decisions.count) decisions")

        let tempDir = FileManager.default.temporaryDirectory
        return try MarkdownExporter.export(meeting: freshMeeting, summary: summary, to: tempDir)
    }

    /// Export as JSON
    public func exportJSON() throws -> URL {
        guard let meeting = meeting else {
            throw ExportError.invalidFormat
        }

        // Re-fetch meeting to ensure relationships are loaded
        guard let freshMeeting = try meetingRepo.fetch(id: meeting.id) else {
            logger.error("Failed to fetch meeting for export: \(meeting.id)")
            throw ExportError.invalidFormat
        }

        logger.debug("Exporting JSON: \(freshMeeting.transcriptChunks.count) transcript chunks, \(freshMeeting.decisions.count) decisions")

        let tempDir = FileManager.default.temporaryDirectory
        return try JSONExporter.export(meeting: freshMeeting, summary: summary, to: tempDir)
    }

    /// Clear messages
    public func clearMessages() {
        errorMessage = nil
        successMessage = nil
    }

    // MARK: - Text Polishing

    /// Beautify/polish the transcript text using Apple Intelligence
    /// Fixes punctuation, capitalization, spelling, splits run-ons, and contextually formats timestamps
    @available(iOS 26, *)
    public func polishTranscript() async {
        guard let meeting = meeting else { return }

        isPolishingText = true
        errorMessage = nil

        do {
            logger.info("Polishing transcript for meeting \(meeting.id)")

            // Extract full transcript
            let rawTranscript = meeting.transcriptChunks
                .sorted { $0.index < $1.index }
                .map(\.text)
                .joined(separator: " ")

            guard !rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                errorMessage = "No transcript to polish"
                isPolishingText = false
                return
            }

            // Use TextPolisher API
            let result = try await TextPolisher.beautify(
                rawTranscript,
                locale: chosenOutputLocale ?? "en-US",
                timeout: 15
            )

            polishedTranscript = result.text
            transcriptEdits = result.edits

            successMessage = "Polished text with \(result.edits.count) improvements"
            logger.info("Transcript polished: \(result.edits.count) edits")
        } catch {
            logger.error("Failed to polish transcript: \(error.localizedDescription)")
            errorMessage = "Failed to polish text: \(error.localizedDescription)"
        }

        isPolishingText = false
    }

    /// Polish individual summary bullets, decisions, or action items
    @available(iOS 26, *)
    public func polishSummaryItems() async {
        guard let currentSummary = summary else { return }

        isPolishingText = true
        errorMessage = nil

        do {
            logger.info("Polishing summary items")

            // Polish bullets
            var polishedBullets: [String] = []
            for bullet in currentSummary.bullets {
                let result = try await TextPolisher.beautify(bullet, locale: chosenOutputLocale)
                polishedBullets.append(result.text)
            }

            // Polish decisions
            var polishedDecisions: [String] = []
            for decision in currentSummary.decisions {
                let result = try await TextPolisher.beautify(decision, locale: chosenOutputLocale)
                polishedDecisions.append(result.text)
            }

            // Polish action items
            var polishedActions: [String] = []
            for action in currentSummary.actionItems {
                let result = try await TextPolisher.beautify(action, locale: chosenOutputLocale)
                polishedActions.append(result.text)
            }

            // Update summary with polished versions
            summary = SummaryResult(
                bullets: polishedBullets,
                decisions: polishedDecisions,
                actionItems: polishedActions
            )

            // Save to meeting
            if let meeting = meeting {
                let encoder = JSONEncoder()
                meeting.summaryJSON = String(data: try encoder.encode(summary), encoding: .utf8)
                try meetingRepo.update(meeting)
            }

            successMessage = "Summary items polished"
            logger.info("Summary items polished successfully")
        } catch {
            logger.error("Failed to polish summary items: \(error.localizedDescription)")
            errorMessage = "Failed to polish summary: \(error.localizedDescription)"
        }

        isPolishingText = false
    }
}
