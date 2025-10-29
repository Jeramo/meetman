//
//  HeuristicSummarizerTests.swift
//  MeetingCopilot
//
//  Unit tests for HeuristicSummarizer
//

import XCTest
@testable import MeetingCopilot

final class HeuristicSummarizerTests: XCTestCase {

    var summarizer: HeuristicSummarizer!

    override func setUp() {
        super.setUp()
        summarizer = HeuristicSummarizer()
    }

    override func tearDown() {
        summarizer = nil
        super.tearDown()
    }

    // MARK: - Summarization Tests

    func testEmptyTranscriptThrows() async {
        do {
            _ = try await summarizer.summarize(transcript: "", maxBullets: 5)
            XCTFail("Should throw for empty transcript")
        } catch LLMError.emptyTranscript {
            // Expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testBasicSummarization() async throws {
        let transcript = """
        We discussed the Q4 roadmap and decided to prioritize the mobile app.
        Alice will lead the design sprint.
        Bob agreed to review the technical architecture by Friday.
        The team discussed budget constraints and resource allocation.
        """

        let result = try await summarizer.summarize(transcript: transcript, maxBullets: 5)

        XCTAssertFalse(result.bullets.isEmpty, "Should extract bullets")
        XCTAssertFalse(result.decisions.isEmpty, "Should extract decisions")
        XCTAssertFalse(result.actionItems.isEmpty, "Should extract action items")
    }

    func testDecisionExtraction() async throws {
        let transcript = """
        We decided to move forward with Option A.
        The team agreed to postpone the feature until next quarter.
        After discussion, we chose the cloud-based solution.
        Management approved the budget increase.
        """

        let result = try await summarizer.summarize(transcript: transcript, maxBullets: 3)

        XCTAssertGreaterThanOrEqual(result.decisions.count, 3, "Should extract multiple decisions")

        let decisionsText = result.decisions.joined().lowercased()
        XCTAssertTrue(decisionsText.contains("decided") || decisionsText.contains("agreed") || decisionsText.contains("approved"))
    }

    func testActionItemExtraction() async throws {
        let transcript = """
        Alice will review the proposal by Friday.
        Bob needs to update the documentation.
        We must schedule a follow-up meeting.
        Action: Review the security audit.
        """

        let result = try await summarizer.summarize(transcript: transcript, maxBullets: 3)

        XCTAssertGreaterThanOrEqual(result.actionItems.count, 1, "Should extract action items")
    }

    func testDeterministicResults() async throws {
        let transcript = "We discussed the project timeline and decided to extend the deadline."

        let result1 = try await summarizer.summarize(transcript: transcript, maxBullets: 5)
        let result2 = try await summarizer.summarize(transcript: transcript, maxBullets: 5)

        XCTAssertEqual(result1, result2, "Should produce deterministic results")
    }

    func testLongTranscriptHandling() async throws {
        // Create a very long transcript
        let sentence = "This is a sentence discussing important project details and decisions. "
        let longTranscript = String(repeating: sentence, count: 500) // ~40k chars

        let result = try await summarizer.summarize(transcript: longTranscript, maxBullets: 7)

        XCTAssertLessThanOrEqual(result.bullets.count, 7, "Should respect max bullets")
        XCTAssertFalse(result.bullets.isEmpty, "Should extract bullets from long text")
    }

    // MARK: - Refinement Tests

    func testRefinement() async throws {
        let initialTranscript = "We discussed the project scope and timeline."
        let initial = try await summarizer.summarize(transcript: initialTranscript, maxBullets: 5)

        let newChunk = "The team decided to add two more features to the roadmap."
        let refined = try await summarizer.refine(context: initial, newChunk: newChunk)

        XCTAssertGreaterThanOrEqual(refined.bullets.count, initial.bullets.count, "Should maintain or add bullets")
        XCTAssertGreaterThan(refined.decisions.count, initial.decisions.count, "Should add new decisions")
    }

    func testRefinementWithEmptyChunk() async throws {
        let context = SummaryResult(
            bullets: ["Bullet 1"],
            decisions: ["Decision 1"],
            actionItems: ["Action 1"]
        )

        let refined = try await summarizer.refine(context: context, newChunk: "")

        XCTAssertEqual(refined, context, "Should return unchanged context for empty chunk")
    }

    func testRefinementDeduplication() async throws {
        let context = SummaryResult(
            bullets: ["Discussed project timeline"],
            decisions: [],
            actionItems: []
        )

        // Add duplicate bullet
        let newChunk = "We discussed the project timeline again."
        let refined = try await summarizer.refine(context: context, newChunk: newChunk)

        // Should deduplicate similar bullets
        XCTAssertLessThanOrEqual(refined.bullets.count, 2, "Should deduplicate similar content")
    }

    // MARK: - Edge Cases

    func testSpecialCharacters() async throws {
        let transcript = """
        Alice said "we should proceed" with the plan.
        Bob's idea was to use C++ for the backend.
        The cost is $10,000 & requires 2-3 weeks.
        """

        let result = try await summarizer.summarize(transcript: transcript, maxBullets: 5)

        XCTAssertFalse(result.bullets.isEmpty, "Should handle special characters")
    }

    func testMultilingualText() async throws {
        // Test with some non-English content
        let transcript = """
        The meeting started at 9:00 AM.
        We discussed café locations and résumé formats.
        The naïve approach was rejected.
        """

        let result = try await summarizer.summarize(transcript: transcript, maxBullets: 5)

        XCTAssertFalse(result.bullets.isEmpty, "Should handle accented characters")
    }

    func testSingleSentenceTranscript() async throws {
        let transcript = "We decided to launch the product next month."

        let result = try await summarizer.summarize(transcript: transcript, maxBullets: 5)

        XCTAssertEqual(result.bullets.count, 1, "Should handle single sentence")
        XCTAssertFalse(result.decisions.isEmpty, "Should extract decision")
    }

    func testNoDecisionsOrActions() async throws {
        let transcript = """
        The weather was nice today.
        People were walking in the park.
        The sun was shining brightly.
        """

        let result = try await summarizer.summarize(transcript: transcript, maxBullets: 3)

        XCTAssertFalse(result.bullets.isEmpty, "Should still extract bullets")
        // Decisions and actions may be empty - that's OK
    }

    // MARK: - Bullet Count Tests

    func testMaxBulletsRespected() async throws {
        let transcript = String(repeating: "Important sentence about the project. ", count: 50)

        let result = try await summarizer.summarize(transcript: transcript, maxBullets: 3)

        XCTAssertLessThanOrEqual(result.bullets.count, 3, "Should respect max bullets limit")
    }

    func testZeroMaxBullets() async throws {
        let transcript = "We discussed the project and made several decisions."

        let result = try await summarizer.summarize(transcript: transcript, maxBullets: 0)

        XCTAssertTrue(result.bullets.isEmpty, "Should return empty bullets for max=0")
    }
}
