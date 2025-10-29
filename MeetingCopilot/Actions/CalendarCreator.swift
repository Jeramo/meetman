//
//  CalendarCreator.swift
//  MeetingCopilot
//
//  EventKit integration for creating calendar events
//

import Foundation
import EventKit
import OSLog

private let logger = Logger(subsystem: "com.jeramo.meetingman", category: "intents")

/// Creates EKEvents from meetings
public final class CalendarCreator: @unchecked Sendable {

    private let eventStore = EKEventStore()
    private var defaultCalendar: EKCalendar?

    public init() {}

    /// Request calendar authorization
    public func requestAuthorization() async throws -> Bool {
        logger.info("Requesting calendar authorization")

        if #available(iOS 17, *) {
            let granted = try await eventStore.requestFullAccessToEvents()
            logger.info("Calendar authorization: \(granted ? "granted" : "denied")")
            return granted
        } else {
            return await withCheckedContinuation { continuation in
                eventStore.requestAccess(to: .event) { granted, error in
                    if let error = error {
                        logger.error("Authorization error: \(error.localizedDescription)")
                    }
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    /// Get or set default calendar
    public func getDefaultCalendar() throws -> EKCalendar {
        if let calendar = defaultCalendar {
            return calendar
        }

        // Try to get default calendar
        if let calendar = eventStore.defaultCalendarForNewEvents {
            defaultCalendar = calendar
            return calendar
        }

        throw ActionsError.noDefaultCalendar
    }

    /// Create calendar event from meeting
    public func createEvent(
        title: String,
        startDate: Date,
        endDate: Date,
        notes: String? = nil,
        meetingURL: URL? = nil
    ) throws -> String {
        logger.info("Creating calendar event: \(title)")

        let calendar = try getDefaultCalendar()

        let event = EKEvent(eventStore: eventStore)
        event.calendar = calendar
        event.title = title
        event.startDate = startDate
        event.endDate = endDate

        // Build notes with deeplink
        var notesText = notes ?? ""
        if let url = meetingURL {
            notesText += "\n\nMeeting recording: \(url.absoluteString)"
        }
        event.notes = notesText

        try eventStore.save(event, span: .thisEvent, commit: true)

        logger.info("Created event: \(event.eventIdentifier ?? "unknown")")
        return event.eventIdentifier ?? ""
    }

    /// Create follow-up event from meeting
    public func createFollowUp(
        for meeting: Meeting,
        title: String? = nil,
        duration: TimeInterval = 3600, // 1 hour default
        daysFromNow: Int = 7
    ) throws -> String {
        let followUpTitle = title ?? "Follow-up: \(meeting.title)"

        // Schedule for same time next week (or specified days)
        let calendar = Calendar.current
        guard let followUpStart = calendar.date(byAdding: .day, value: daysFromNow, to: meeting.startedAt) else {
            throw ActionsError.creationFailed(underlying: NSError(domain: "DateCalculation", code: -1))
        }
        let followUpEnd = followUpStart.addingTimeInterval(duration)

        // Build notes with reference to original meeting
        let notes = """
        Follow-up to meeting from \(meeting.startedAt.formatted(date: .long, time: .shortened))

        Original attendees: \(meeting.attendees.map(\.name).joined(separator: ", "))
        """

        let deeplink = URL(string: "meetingcopilot://meeting/\(meeting.id.uuidString)")

        return try createEvent(
            title: followUpTitle,
            startDate: followUpStart,
            endDate: followUpEnd,
            notes: notes,
            meetingURL: deeplink
        )
    }
}
