//
//  StopMeetingIntent.swift
//  MeetingCopilot
//
//  App Intent to stop the active meeting
//

import Foundation
import AppIntents
import OSLog

private let logger = Logger(subsystem: "com.jeramo.meetingman", category: "intents")

/// Stop the active meeting recording
@available(iOS 26, *)
struct StopMeetingIntent: AppIntent {

    nonisolated(unsafe) static var title: LocalizedStringResource = "Stop Meeting"
    nonisolated(unsafe) static var description = IntentDescription("Stop the current meeting recording")

    nonisolated(unsafe) static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        logger.info("Stopping meeting via intent")

        let context = Store.shared.backgroundContext()
        let repo = MeetingRepository(context: context)

        // Find active meeting
        guard let meeting = try repo.getActiveMeeting() else {
            logger.warning("No active meeting to stop")
            return .result(
                dialog: "No active meeting found"
            )
        }

        // End meeting
        try repo.endMeeting(meeting)

        logger.info("Stopped meeting via intent: \(meeting.id)")

        // TODO: Schedule background task to complete summary

        return .result(
            dialog: "Stopped recording '\(meeting.title)'"
        )
    }
}
