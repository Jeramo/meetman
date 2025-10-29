//
//  ExporterTests.swift
//  MeetingCopilot
//
//  Unit tests for Markdown and JSON exporters
//

import XCTest
@testable import MeetingCopilot

final class ExporterTests: XCTestCase {

    var tempDirectory: URL!
    var testMeeting: Meeting!
    var testSummary: SummaryResult!

    override func setUp() {
        super.setUp()

        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        // Create test meeting
        testMeeting = Meeting(
            title: "Test Meeting",
            attendees: [
                PersonRef(name: "Alice", email: "alice@example.com"),
                PersonRef(name: "Bob")
            ]
        )

        testMeeting.endedAt = testMeeting.startedAt.addingTimeInterval(3600) // 1 hour

        // Add transcript chunks
        testMeeting.transcriptChunks = [
            TranscriptChunk(
                meetingID: testMeeting.id,
                index: 0,
                text: "We discussed the project roadmap.",
                startTime: 0,
                endTime: 5
            ),
            TranscriptChunk(
                meetingID: testMeeting.id,
                index: 1,
                text: "Alice will lead the design sprint.",
                startTime: 5,
                endTime: 10
            )
        ]

        // Add decisions
        testMeeting.decisions = [
            Decision(
                meetingID: testMeeting.id,
                text: "Decided to use SwiftUI",
                owner: "Team"
            )
        ]

        // Create test summary
        testSummary = SummaryResult(
            bullets: [
                "Discussed Q4 roadmap",
                "Reviewed budget allocation"
            ],
            decisions: [
                "Decided to prioritize mobile app"
            ],
            actionItems: [
                "Alice — Design — mockups by Friday",
                "Bob — Review — architecture"
            ]
        )
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        tempDirectory = nil
        testMeeting = nil
        testSummary = nil
        super.tearDown()
    }

    // MARK: - Markdown Tests

    func testMarkdownRenderWithSummary() {
        let markdown = MarkdownExporter.render(meeting: testMeeting, summary: testSummary)

        XCTAssertTrue(markdown.contains("# Test Meeting"))
        XCTAssertTrue(markdown.contains("## Summary"))
        XCTAssertTrue(markdown.contains("Discussed Q4 roadmap"))
        XCTAssertTrue(markdown.contains("## Decisions"))
        XCTAssertTrue(markdown.contains("Decided to prioritize mobile app"))
        XCTAssertTrue(markdown.contains("## Action Items"))
        XCTAssertTrue(markdown.contains("Alice — Design — mockups by Friday"))
    }

    func testMarkdownRenderWithoutSummary() {
        let markdown = MarkdownExporter.render(meeting: testMeeting, summary: nil)

        XCTAssertTrue(markdown.contains("# Test Meeting"))
        XCTAssertTrue(markdown.contains("**Attendees:** Alice, Bob"))
        XCTAssertTrue(markdown.contains("## Transcript"))
        XCTAssertTrue(markdown.contains("We discussed the project roadmap"))
    }

    func testMarkdownExportToFile() throws {
        let fileURL = try MarkdownExporter.export(
            meeting: testMeeting,
            summary: testSummary,
            to: tempDirectory
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertEqual(fileURL.pathExtension, "md")

        let content = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(content.contains("# Test Meeting"))
    }

    func testMarkdownDurationFormatting() {
        let markdown = MarkdownExporter.render(meeting: testMeeting, summary: nil)

        XCTAssertTrue(markdown.contains("**Duration:**"))
        XCTAssertTrue(markdown.contains("1h 0m") || markdown.contains("60m"))
    }

    func testMarkdownAttendeesList() {
        let markdown = MarkdownExporter.render(meeting: testMeeting, summary: nil)

        XCTAssertTrue(markdown.contains("Alice"))
        XCTAssertTrue(markdown.contains("Bob"))
    }

    // MARK: - JSON Tests

    func testJSONExport() throws {
        let fileURL = try JSONExporter.export(
            meeting: testMeeting,
            summary: testSummary,
            to: tempDirectory
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertEqual(fileURL.pathExtension, "json")

        let data = try Data(contentsOf: fileURL)
        let decoded = try JSONDecoder().decode([String: AnyCodable].self, from: data)

        XCTAssertNotNil(decoded["id"])
        XCTAssertNotNil(decoded["title"])
        XCTAssertNotNil(decoded["transcript"])
    }

    func testJSONStructure() throws {
        let fileURL = try JSONExporter.export(
            meeting: testMeeting,
            summary: testSummary,
            to: tempDirectory
        )

        let data = try Data(contentsOf: fileURL)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["title"] as? String, "Test Meeting")
        XCTAssertNotNil(json["attendees"])
        XCTAssertNotNil(json["summary"])
        XCTAssertNotNil(json["decisions"])
    }

    func testJSONPrettyPrinting() throws {
        let fileURL = try JSONExporter.export(
            meeting: testMeeting,
            summary: testSummary,
            to: tempDirectory
        )

        let content = try String(contentsOf: fileURL, encoding: .utf8)

        // Pretty-printed JSON should contain newlines and indentation
        XCTAssertTrue(content.contains("\n"))
        XCTAssertTrue(content.contains("  ")) // Indentation
    }

    // MARK: - Filename Tests

    func testFilenameGeneration() throws {
        let fileURL = try MarkdownExporter.export(
            meeting: testMeeting,
            summary: nil,
            to: tempDirectory
        )

        let filename = fileURL.lastPathComponent
        XCTAssertTrue(filename.contains("Test_Meeting"))
        XCTAssertTrue(filename.hasSuffix(".md"))
    }

    func testFilenameSanitization() throws {
        // Meeting with special characters
        let specialMeeting = Meeting(title: "Test/Meeting:With*Special?Chars")
        specialMeeting.endedAt = Date()

        let fileURL = try MarkdownExporter.export(
            meeting: specialMeeting,
            summary: nil,
            to: tempDirectory
        )

        let filename = fileURL.lastPathComponent

        // Should not contain invalid characters
        XCTAssertFalse(filename.contains("/"))
        XCTAssertFalse(filename.contains(":"))
        XCTAssertFalse(filename.contains("*"))
        XCTAssertFalse(filename.contains("?"))
    }

    // MARK: - Edge Cases

    func testExportEmptyMeeting() throws {
        let emptyMeeting = Meeting(title: "Empty Meeting")
        emptyMeeting.endedAt = Date()

        let markdown = MarkdownExporter.render(meeting: emptyMeeting, summary: nil)

        XCTAssertTrue(markdown.contains("# Empty Meeting"))
        // Should not crash with empty transcript
        XCTAssertTrue(markdown.contains("## Transcript"))
    }

    func testExportUnicodeContent() throws {
        let unicodeMeeting = Meeting(title: "Café Meeting ☕️")
        unicodeMeeting.transcriptChunks = [
            TranscriptChunk(
                meetingID: unicodeMeeting.id,
                index: 0,
                text: "Discussed naïve approaches to résumé parsing",
                startTime: 0,
                endTime: 5
            )
        ]

        let markdown = MarkdownExporter.render(meeting: unicodeMeeting, summary: nil)

        XCTAssertTrue(markdown.contains("Café"))
        XCTAssertTrue(markdown.contains("naïve"))
        XCTAssertTrue(markdown.contains("résumé"))
    }
}

// MARK: - Helper Type

struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let int = try? container.decode(Int.self) {
            value = int
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else {
            value = "unknown"
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let int = value as? Int {
            try container.encode(int)
        } else if let string = value as? String {
            try container.encode(string)
        } else if let bool = value as? Bool {
            try container.encode(bool)
        } else if let double = value as? Double {
            try container.encode(double)
        }
    }
}
