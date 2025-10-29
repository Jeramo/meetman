//
//  ProfanitySanitizerTests.swift
//  MeetingCopilot
//
//  Tests for profanity sanitization functionality
//  Note: ProfanitySanitizer is defined in AppleIntelligenceClient.swift
//

import XCTest
@testable import MeetingCopilot

final class ProfanitySanitizerTests: XCTestCase {

    // MARK: - English Tests

    func testEnglishProfanityRedaction() {
        let input = "This is shit and fucking annoying."
        let sanitized = ProfanitySanitizer.sanitize(input, mode: .redact)

        XCTAssertTrue(sanitized.contains("[expletive]"))
        XCTAssertFalse(sanitized.lowercased().contains("shit"))
        XCTAssertFalse(sanitized.lowercased().contains("fucking"))
    }

    func testEnglishProfanityMasking() {
        let input = "What the hell is this shit?"
        let sanitized = ProfanitySanitizer.sanitize(input, mode: .mask)

        // Should mask profanity (e.g., "h*l" or "s**t")
        XCTAssertFalse(sanitized.lowercased().contains("hell"))
        XCTAssertFalse(sanitized.lowercased().contains("shit"))
        XCTAssertTrue(sanitized.contains("*"))
    }

    func testCaseInsensitiveEnglish() {
        let inputs = [
            "This is SHIT",
            "This is Shit",
            "This is ShIt"
        ]

        for input in inputs {
            let sanitized = ProfanitySanitizer.sanitize(input)
            XCTAssertFalse(sanitized.lowercased().contains("shit"))
            XCTAssertTrue(sanitized.contains("[expletive]"))
        }
    }

    // MARK: - Swedish Tests

    func testSwedishProfanityRedaction() {
        let input = "Detta är skit och jävla irriterande."
        let sanitized = ProfanitySanitizer.sanitize(input, mode: .redact)

        XCTAssertTrue(sanitized.contains("[expletive]"))
        XCTAssertFalse(sanitized.lowercased().contains("skit"))
        XCTAssertFalse(sanitized.lowercased().contains("jävla"))
    }

    func testSwedishProfanityMasking() {
        let input = "Vad fan är det här?"
        let sanitized = ProfanitySanitizer.sanitize(input, mode: .mask)

        XCTAssertFalse(sanitized.lowercased().contains("fan"))
        XCTAssertTrue(sanitized.contains("*"))
    }

    // MARK: - Mixed Language Tests

    func testMixedLanguageProfanity() {
        let input = "This shit är jävla bad."
        let sanitized = ProfanitySanitizer.sanitize(input)

        // Both English and Swedish profanity should be redacted
        XCTAssertFalse(sanitized.lowercased().contains("shit"))
        XCTAssertFalse(sanitized.lowercased().contains("jävla"))
        XCTAssertTrue(sanitized.contains("[expletive]"))
    }

    // MARK: - Edge Cases

    func testNoProfanity() {
        let input = "This is a clean sentence."
        let sanitized = ProfanitySanitizer.sanitize(input)

        // Should remain unchanged
        XCTAssertEqual(input, sanitized)
        XCTAssertFalse(sanitized.contains("[expletive]"))
    }

    func testEmptyString() {
        let input = ""
        let sanitized = ProfanitySanitizer.sanitize(input)

        XCTAssertEqual(input, sanitized)
    }

    func testWhitespaceOnly() {
        let input = "   \n\t   "
        let sanitized = ProfanitySanitizer.sanitize(input)

        XCTAssertEqual(input, sanitized)
    }

    func testWordBoundaries() {
        // Should NOT redact partial matches
        let input = "The class contains classification data."
        let sanitized = ProfanitySanitizer.sanitize(input)

        // "class" contains "ass" but shouldn't be redacted due to word boundaries
        XCTAssertEqual(input, sanitized)
    }

    func testMultipleProfanitiesInSentence() {
        let input = "This shit is fucking terrible, what the hell?"
        let sanitized = ProfanitySanitizer.sanitize(input)

        // All profanity should be redacted
        XCTAssertFalse(sanitized.lowercased().contains("shit"))
        XCTAssertFalse(sanitized.lowercased().contains("fucking"))
        XCTAssertFalse(sanitized.lowercased().contains("hell"))

        // Should have multiple expletive markers
        let expletiveCount = sanitized.components(separatedBy: "[expletive]").count - 1
        XCTAssertEqual(expletiveCount, 3)
    }

    func testRepeatedProfanity() {
        let input = "Shit shit shit!"
        let sanitized = ProfanitySanitizer.sanitize(input)

        XCTAssertFalse(sanitized.lowercased().contains("shit"))

        // Should have 3 expletive markers
        let expletiveCount = sanitized.components(separatedBy: "[expletive]").count - 1
        XCTAssertEqual(expletiveCount, 3)
    }

    // MARK: - Detection Tests

    func testContainsProfanity() {
        XCTAssertTrue(ProfanitySanitizer.containsProfanity("This is shit"))
        XCTAssertTrue(ProfanitySanitizer.containsProfanity("Detta är jävla dumt"))
        XCTAssertFalse(ProfanitySanitizer.containsProfanity("This is clean"))
        XCTAssertFalse(ProfanitySanitizer.containsProfanity(""))
    }

    func testContainsProfanityCaseInsensitive() {
        XCTAssertTrue(ProfanitySanitizer.containsProfanity("SHIT"))
        XCTAssertTrue(ProfanitySanitizer.containsProfanity("ShIt"))
        XCTAssertTrue(ProfanitySanitizer.containsProfanity("JÄVLA"))
    }

    // MARK: - Real World Scenarios

    func testMeetingTranscriptWithProfanity() {
        let transcript = """
        Vi diskuterade projektet och det var jävla bra.
        Alice sa att deadline är shit men vi fixar det.
        Bob höll med och sa fuck it, vi kör på.
        """

        let sanitized = ProfanitySanitizer.sanitize(transcript)

        // All profanity should be gone
        XCTAssertFalse(sanitized.lowercased().contains("jävla"))
        XCTAssertFalse(sanitized.lowercased().contains("shit"))
        XCTAssertFalse(sanitized.lowercased().contains("fuck"))

        // But names and context should remain
        XCTAssertTrue(sanitized.contains("Alice"))
        XCTAssertTrue(sanitized.contains("Bob"))
        XCTAssertTrue(sanitized.contains("projektet"))
        XCTAssertTrue(sanitized.contains("deadline"))
    }

    func testPersonalConversationWithProfanity() {
        let transcript = "Jag älskar dig du är så fin älskling, men fan vad trött jag är!"
        let sanitized = ProfanitySanitizer.sanitize(transcript)

        XCTAssertFalse(sanitized.lowercased().contains("fan"))
        XCTAssertTrue(sanitized.contains("älskar"))
        XCTAssertTrue(sanitized.contains("älskling"))
    }

    // MARK: - Performance Tests

    func testSanitizationPerformance() {
        let longTranscript = String(repeating: "This is shit and fucking annoying. ", count: 1000)

        measure {
            _ = ProfanitySanitizer.sanitize(longTranscript)
        }
    }
}
