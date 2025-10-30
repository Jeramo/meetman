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
    public var isDiarizing = false
    public var diarizationProgress: Double = 0
    public var diarizationStatus: String = ""
    public var errorMessage: String?
    public var successMessage: String?

    /// Chosen output locale for summary generation (e.g., "en-us" fallback for unsupported languages)
    public var chosenOutputLocale: String?

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

            // Get chunks sorted
            let chunks = meeting.transcriptChunks.sorted { $0.index < $1.index }
            let nonEmptyChunks = chunks.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

            // Polish each chunk individually for better display with timestamps (iOS 26+)
            var polishedChunks: [String] = []
            if #available(iOS 26, *) {
                for chunk in nonEmptyChunks {
                    do {
                        logger.debug("Polishing chunk \(chunk.index)...")
                        let polished = try await TextPolisher.beautify(chunk.text, timeout: 20)
                        chunk.polishedText = polished.text
                        polishedChunks.append(polished.text)
                        logger.debug("Chunk \(chunk.index) polished: \(polished.edits.count) edits")
                    } catch {
                        logger.warning("Failed to polish chunk \(chunk.index): \(error.localizedDescription)")
                        chunk.polishedText = nil
                        polishedChunks.append(chunk.text)
                    }
                }

                // Join polished chunks for full transcript
                let polishedFullTranscript = polishedChunks.joined(separator: " ")
                meeting.polishedTranscript = polishedFullTranscript
                logger.info("Transcript polishing complete for \(nonEmptyChunks.count) chunks")
            } else {
                // iOS 25 and below: no polishing available
                polishedChunks = nonEmptyChunks.map(\.text)
                meeting.polishedTranscript = nil
            }

            // Check for preferred output locale from user choice during capture
            let preferredLocale = chosenOutputLocale ?? UserDefaults.standard.string(forKey: "preferred.output.locale")

            // Use polished transcript for summarization (better quality)
            // If speaker diarization has been performed, include speaker labels
            let hasSpeakers = nonEmptyChunks.contains { $0.speakerID != nil }
            let transcriptForSummary: String

            if hasSpeakers {
                // Format with speaker labels: "S1: text\nS2: text\n..."
                transcriptForSummary = zip(nonEmptyChunks, polishedChunks)
                    .map { chunk, polishedText in
                        if let speakerID = chunk.speakerID {
                            return "\(speakerID): \(polishedText)"
                        } else {
                            return polishedText
                        }
                    }
                    .joined(separator: "\n")
                logger.info("Using speaker-tagged transcript for summary")
            } else {
                transcriptForSummary = polishedChunks.joined(separator: " ")
            }

            summary = try await nlpService.summarize(transcript: transcriptForSummary, forceOutputLocale: preferredLocale)

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

    /// Perform speaker diarization on meeting audio
    public func performDiarization() async {
        guard let meeting = meeting else { return }

        isDiarizing = true
        errorMessage = nil
        diarizationProgress = 0
        diarizationStatus = "Starting..."

        do {
            logger.info("Starting diarization for meeting \(meeting.id)")

            // Create service with explicit nonisolated context
            let service = DiarizationService(
                embedderURL: nil, // nil = heuristic fallback
                context: context
            )

            // Use @Sendable closure to satisfy concurrency requirements
            _ = try await service.diarize(meeting: meeting) { @Sendable progress, status in
                Task { @MainActor in
                    self.diarizationProgress = progress
                    self.diarizationStatus = status
                }
            }

            successMessage = "Speaker identification complete"
            logger.info("Diarization complete")
        } catch {
            logger.error("Failed to perform diarization: \(error.localizedDescription)")
            errorMessage = "Failed to identify speakers: \(error.localizedDescription)"
        }

        isDiarizing = false
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
}
