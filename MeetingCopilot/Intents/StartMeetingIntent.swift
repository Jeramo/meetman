//
//  StartMeetingIntent.swift
//  MeetingCopilot
//
//  App Intent to start a meeting recording
//

import Foundation
import AppIntents
import OSLog

private let logger = Logger(subsystem: "com.jeramo.meetingman", category: "intents")

/// Start a new meeting recording
@available(iOS 26, *)
struct StartMeetingIntent: AppIntent {

    nonisolated(unsafe) static var title: LocalizedStringResource = "Start Meeting"
    nonisolated(unsafe) static var description = IntentDescription("Start recording a new meeting")

    nonisolated(unsafe) static var openAppWhenRun: Bool = true

    @Parameter(title: "Meeting Title")
    var title: String?

    @Parameter(title: "Attendees")
    var attendees: [String]?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        logger.info("Starting meeting via intent")

        let meetingTitle = title ?? "Meeting \(Date().formatted(date: .abbreviated, time: .shortened))"

        // Convert attendees to PersonRef
        let personRefs = (attendees ?? []).map { PersonRef(name: $0) }

        // Create meeting
        let context = Store.shared.backgroundContext()
        let repo = MeetingRepository(context: context)

        do {
            let meeting = try repo.create(title: meetingTitle, attendees: personRefs)

            logger.info("Created meeting via intent: \(meeting.id)")

            return .result(
                dialog: "Started recording '\(meetingTitle)'"
            )
        } catch {
            logger.error("Failed to start meeting: \(error.localizedDescription)")
            throw error
        }
    }
}
