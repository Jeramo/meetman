//
//  GenerateSummaryIntent.swift
//  MeetingCopilot
//
//  App Intent to generate and export meeting summary
//

import Foundation
import AppIntents
import OSLog

private let logger = Logger(subsystem: "com.jeramo.meetingman", category: "intents")

/// Generate summary for a meeting
@available(iOS 26, *)
struct GenerateSummaryIntent: AppIntent {

    nonisolated(unsafe) static var title: LocalizedStringResource = "Generate Summary"
    nonisolated(unsafe) static var description = IntentDescription("Generate a summary for a meeting")

    nonisolated(unsafe) static var openAppWhenRun: Bool = false

    @Parameter(title: "Meeting ID")
    var meetingID: String?

    @Parameter(title: "Export Format", default: .markdown)
    var format: ExportFormat

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<IntentFile> {
        logger.info("Generating summary via intent")

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
            logger.warning("No meeting found for summary")
            throw NSError(domain: "MeetingCopilot", code: 404, userInfo: [NSLocalizedDescriptionKey: "No meeting found"])
        }

        // Generate summary if not exists
        let summary: SummaryResult
        if let summaryJSON = meeting.summaryJSON,
           let data = summaryJSON.data(using: .utf8),
           let existing = try? JSONDecoder().decode(SummaryResult.self, from: data) {
            summary = existing
            logger.info("Using existing summary")
        } else {
            // Generate new summary
            logger.info("Generating new summary")

            // Extract transcript text
            let transcript = meeting.transcriptChunks
                .sorted { $0.index < $1.index }
                .map(\.text)
                .joined(separator: " ")

            let nlp = NLPService()
            summary = try await nlp.summarize(transcript: transcript)

            // Save to meeting
            let encoder = JSONEncoder()
            meeting.summaryJSON = String(data: try encoder.encode(summary), encoding: .utf8)
            try meetingRepo.update(meeting)
        }

        // Export to temp directory
        let tempDir = FileManager.default.temporaryDirectory

        let fileURL: URL
        switch format {
        case .markdown:
            fileURL = try MarkdownExporter.export(meeting: meeting, summary: summary, to: tempDir)
        case .json:
            fileURL = try JSONExporter.export(meeting: meeting, summary: summary, to: tempDir)
        }

        logger.info("Exported summary to \(fileURL.lastPathComponent)")

        let file = IntentFile(fileURL: fileURL, filename: fileURL.lastPathComponent)

        return .result(
            value: file,
            dialog: "Summary generated and exported"
        )
    }
}

/// Export format enum
enum ExportFormat: String, AppEnum {
    case markdown
    case json

    nonisolated(unsafe) static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Export Format")

    nonisolated(unsafe) static var caseDisplayRepresentations: [ExportFormat: DisplayRepresentation] = [
        .markdown: "Markdown",
        .json: "JSON"
    ]
}
