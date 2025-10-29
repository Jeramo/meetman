//
//  CreateNextStepsIntent.swift
//  MeetingCopilot
//
//  App Intent to create reminders from action items
//

import Foundation
import AppIntents
import OSLog

private let logger = Logger(subsystem: "com.jeramo.meetingman", category: "intents")

/// Create reminders from meeting action items
@available(iOS 26, *)
struct CreateNextStepsIntent: AppIntent {

    nonisolated(unsafe) static var title: LocalizedStringResource = "Create Next Steps"
    nonisolated(unsafe) static var description = IntentDescription("Create reminders from meeting action items")

    nonisolated(unsafe) static var openAppWhenRun: Bool = false

    @Parameter(title: "Meeting ID")
    var meetingID: String?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        logger.info("Creating next steps via intent")

        let context = Store.shared.backgroundContext()
        let meetingRepo = MeetingRepository(context: context)

        // Find meeting (active or specified)
        let meeting: Meeting?
        if let idString = meetingID, let uuid = UUID(uuidString: idString) {
            meeting = try meetingRepo.fetch(id: uuid)
        } else {
            meeting = try meetingRepo.getActiveMeeting()
        }

        guard let meeting = meeting else {
            logger.warning("No meeting found for creating next steps")
            return .result(
                dialog: "No meeting found"
            )
        }

        // Parse summary to get action items
        guard let summaryJSON = meeting.summaryJSON,
              let data = summaryJSON.data(using: .utf8),
              let summary = try? JSONDecoder().decode(SummaryResult.self, from: data) else {
            logger.warning("No summary found for meeting")
            return .result(
                dialog: "Please generate a summary first"
            )
        }

        guard !summary.actionItems.isEmpty else {
            return .result(
                dialog: "No action items found in this meeting"
            )
        }

        // Create reminders
        let taskCreator = TaskCreator()

        do {
            let reminderIDs = try await taskCreator.createReminders(
                from: summary.actionItems,
                meetingTitle: meeting.title
            )

            logger.info("Created \(reminderIDs.count) reminders")

            return .result(
                dialog: "Created \(reminderIDs.count) reminders from action items"
            )
        } catch {
            logger.error("Failed to create reminders: \(error.localizedDescription)")
            throw error
        }
    }
}
