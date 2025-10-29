//
//  TaskCreator.swift
//  MeetingCopilot
//
//  EventKit integration for creating reminders from action items
//

import Foundation
import EventKit
import OSLog

private let logger = Logger(subsystem: "com.jeramo.meetingman", category: "intents")

/// Creates EKReminders from action items
public final class TaskCreator: @unchecked Sendable {

    private let eventStore = EKEventStore()
    private var defaultList: EKCalendar?

    public init() {}

    /// Request reminders authorization
    public func requestAuthorization() async throws -> Bool {
        logger.info("Requesting reminders authorization")

        if #available(iOS 17, *) {
            let granted = try await eventStore.requestFullAccessToReminders()
            logger.info("Reminders authorization: \(granted ? "granted" : "denied")")
            return granted
        } else {
            return await withCheckedContinuation { continuation in
                eventStore.requestAccess(to: .reminder) { granted, error in
                    if let error = error {
                        logger.error("Authorization error: \(error.localizedDescription)")
                    }
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    /// Get or set default reminder list
    public func getDefaultList() throws -> EKCalendar {
        if let list = defaultList {
            return list
        }

        // Try to get default calendar
        if let list = eventStore.defaultCalendarForNewReminders() {
            defaultList = list
            return list
        }

        throw ActionsError.noDefaultReminderList
    }

    /// Create reminder from action item
    public func createReminder(
        title: String,
        notes: String? = nil,
        dueDate: Date? = nil,
        priority: Int = 0
    ) throws -> String {
        logger.info("Creating reminder: \(title)")

        let list = try getDefaultList()

        let reminder = EKReminder(eventStore: eventStore)
        reminder.calendar = list
        reminder.title = title
        reminder.notes = notes
        reminder.priority = priority

        if let dueDate = dueDate {
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
            reminder.dueDateComponents = components
        }

        try eventStore.save(reminder, commit: true)

        logger.info("Created reminder: \(reminder.calendarItemIdentifier)")
        return reminder.calendarItemIdentifier
    }

    /// Create reminders from action items
    public func createReminders(from actionItems: [String], meetingTitle: String) async throws -> [String] {
        // Request auth if needed
        let status = EKEventStore.authorizationStatus(for: .reminder)
        if status != .fullAccess && status != .writeOnly {
            let granted = try await requestAuthorization()
            guard granted else {
                throw ActionsError.remindersPermissionDenied
            }
        }

        var reminderIDs: [String] = []

        for item in actionItems {
            do {
                let (title, dueDate) = parseActionItem(item)
                let notes = "From meeting: \(meetingTitle)"

                let id = try createReminder(
                    title: title,
                    notes: notes,
                    dueDate: dueDate,
                    priority: 1
                )

                reminderIDs.append(id)
            } catch {
                logger.error("Failed to create reminder for '\(item)': \(error.localizedDescription)")
                throw ActionsError.creationFailed(underlying: error)
            }
        }

        logger.info("Created \(reminderIDs.count) reminders")
        return reminderIDs
    }

    /// Parse action item to extract title and optional due date
    private func parseActionItem(_ item: String) -> (title: String, dueDate: Date?) {
        // Try to extract due date patterns like "by Friday", "by Dec 15", etc.
        let datePatterns = [
            #"\s+by\s+(\w+\s+\d{1,2})"#,      // "by Dec 15"
            #"\s+by\s+(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday)"#, // "by Friday"
            #"\s+due\s+(\w+\s+\d{1,2})"#       // "due Dec 15"
        ]

        var title = item
        var dueDate: Date?

        for patternString in datePatterns {
            if let regex = try? NSRegularExpression(pattern: patternString, options: .caseInsensitive) {
                let range = NSRange(item.startIndex..<item.endIndex, in: item)
                if let match = regex.firstMatch(in: item, options: [], range: range) {
                    // Extract date string
                    if let dateRange = Range(match.range(at: 1), in: item) {
                        let dateString = String(item[dateRange])
                        dueDate = parseDateString(dateString)
                    }

                    // Remove date from title
                    if let matchRange = Range(match.range, in: item) {
                        title = String(item[..<matchRange.lowerBound])
                    }
                    break
                }
            }
        }

        return (title.trimmingCharacters(in: .whitespacesAndNewlines), dueDate)
    }

    private func parseDateString(_ dateString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale.current

        // Try various formats
        let formats = [
            "MMM d",       // "Dec 15"
            "MMMM d",      // "December 15"
            "EEEE",        // "Friday"
            "EEE"          // "Fri"
        ]

        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: dateString) {
                // If parsed as weekday, find next occurrence
                if format.contains("E") {
                    return nextWeekday(matching: date)
                }
                return date
            }
        }

        return nil
    }

    private func nextWeekday(matching date: Date) -> Date {
        let calendar = Calendar.current
        let targetWeekday = calendar.component(.weekday, from: date)
        let today = Date()
        let currentWeekday = calendar.component(.weekday, from: today)

        var daysToAdd = targetWeekday - currentWeekday
        if daysToAdd <= 0 {
            daysToAdd += 7
        }

        return calendar.date(byAdding: .day, value: daysToAdd, to: today) ?? today
    }
}
