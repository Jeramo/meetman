//
//  MarkDecisionIntent.swift
//  MeetingCopilot
//
//  App Intent to mark a decision during a meeting
//

import Foundation
import AppIntents
import OSLog

private let logger = Logger(subsystem: "com.jeramo.meetingman", category: "intents")

/// Mark a decision in the current meeting
@available(iOS 26, *)
struct MarkDecisionIntent: AppIntent {

    nonisolated(unsafe) static var title: LocalizedStringResource = "Mark Decision"
    nonisolated(unsafe) static var description = IntentDescription("Add a decision to the current meeting")

    nonisolated(unsafe) static var openAppWhenRun: Bool = false

    @Parameter(title: "Decision Text", requestValueDialog: "What was decided?")
    var text: String

    @Parameter(title: "Owner")
    var owner: String?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        logger.info("Marking decision via intent")

        let context = Store.shared.backgroundContext()
        let meetingRepo = MeetingRepository(context: context)
        let decisionRepo = DecisionRepository(context: context)

        // Find active meeting
        guard let meeting = try meetingRepo.getActiveMeeting() else {
            logger.warning("No active meeting for decision")
            return .result(
                dialog: "No active meeting. Start a meeting first."
            )
        }

        // Add decision
        _ = try decisionRepo.add(meetingID: meeting.id, text: text, owner: owner)

        logger.info("Added decision to meeting \(meeting.id)")

        return .result(
            dialog: "Decision recorded"
        )
    }
}
