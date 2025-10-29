//
//  BackgroundTasks.swift
//  MeetingCopilot
//
//  Background processing for post-meeting summarization
//

import Foundation
@preconcurrency import BackgroundTasks
import OSLog

private let logger = Logger(subsystem: "com.jeramo.meetingman", category: "background")

/// Background task identifiers
public enum BackgroundTaskIdentifier {
    public static let summarize = "com.jeramo.meetingman.summarize"
}

/// Manager for background task scheduling and execution
@available(iOS 26, *)
public final class BackgroundTaskManager: @unchecked Sendable {

    public static let shared = BackgroundTaskManager()

    private init() {}

    /// Register background task handlers
    public func registerTasks() {
        logger.info("Registering background tasks")

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: BackgroundTaskIdentifier.summarize,
            using: nil
        ) { task in
            self.handleSummarizeTask(task as! BGProcessingTask)
        }
    }

    /// Schedule summarization task for a meeting
    public func scheduleSummarization(for meetingID: UUID) {
        logger.info("Scheduling summarization for meeting \(meetingID)")

        let request = BGProcessingTaskRequest(identifier: BackgroundTaskIdentifier.summarize)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false

        // Run as soon as possible (caller ensures data is saved)
        request.earliestBeginDate = Date()

        do {
            try BGTaskScheduler.shared.submit(request)
            logger.info("Scheduled background summarization")
        } catch {
            logger.error("Failed to schedule background task: \(error.localizedDescription)")
        }
    }

    /// Handle summarization background task
    private func handleSummarizeTask(_ task: BGProcessingTask) {
        logger.info("Executing background summarization task")

        // Create task for async work
        let workTask = Task {
            await performSummarization()
            return true
        }

        // Handle expiration
        task.expirationHandler = {
            logger.warning("Background task expired, cancelling")
            workTask.cancel()
        }

        // Wait for completion and mark task as done
        // This is safe because we don't capture task in the async context
        Task {
            let success = await workTask.value
            task.setTaskCompleted(success: success)
            logger.info("Background summarization completed: \(success)")
        }
    }

    /// Perform summarization in background
    private func performSummarization() async {
        logger.info("Starting background summarization")

        // Small delay to ensure file system writes from main context are visible
        try? await Task.sleep(for: .milliseconds(100))

        let context = Store.shared.backgroundContext()
        let meetingRepo = MeetingRepository(context: context)

        do {
            // Find recent meetings without summaries
            let allMeetings = try meetingRepo.fetchAll()
            let unsummarized = allMeetings.filter { meeting in
                meeting.summaryJSON == nil && meeting.endedAt != nil
            }

            guard let meeting = unsummarized.first else {
                logger.info("No meetings need summarization")
                return
            }

            logger.info("Generating summary for meeting \(meeting.id)")

            // Use the meeting's transcriptChunks relationship (SwiftData will fetch them)
            let chunks = meeting.transcriptChunks
            logger.info("Found \(chunks.count) transcript chunks via relationship")

            // Extract transcript text, filtering empty chunks
            let nonEmptyChunks = chunks.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            logger.info("Found \(nonEmptyChunks.count) non-empty chunks")

            let transcript = nonEmptyChunks
                .sorted { $0.index < $1.index }
                .map(\.text)
                .joined(separator: " ")

            logger.info("Full transcript length: \(transcript.count) characters")
            logger.debug("Original transcript (first 200 chars): \(transcript.prefix(200))")

            // Polish transcript before summarization for better quality
            let polished: PolishedText
            do {
                logger.info("Polishing transcript with Apple Intelligence...")
                polished = try await TextPolisher.beautify(transcript, timeout: 15)
                logger.info("Transcript polished: \(polished.edits.count) improvements made")
                logger.debug("Polished transcript (first 200 chars): \(polished.text.prefix(200))")

                // Store polished version for display
                meeting.polishedTranscript = polished.text
            } catch {
                logger.warning("Failed to polish transcript, using original: \(error.localizedDescription)")
                // Fallback: use original if polishing fails
                polished = PolishedText(text: transcript, edits: [])
                meeting.polishedTranscript = nil
            }

            // Generate summary from polished (clean) text
            let nlp = NLPService()
            let summary = try await nlp.summarize(transcript: polished.text)

            // Save to meeting
            let encoder = JSONEncoder()
            meeting.summaryJSON = String(data: try encoder.encode(summary), encoding: .utf8)
            try meetingRepo.update(meeting)

            logger.info("Successfully summarized meeting in background")
        } catch {
            logger.error("Background summarization failed: \(error.localizedDescription)")
        }
    }

    /// Cancel all pending tasks
    public func cancelAllTasks() {
        logger.info("Cancelling all background tasks")
        BGTaskScheduler.shared.cancelAllTaskRequests()
    }
}
