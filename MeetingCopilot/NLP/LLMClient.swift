//
//  LLMClient.swift
//  MeetingCopilot
//
//  Protocol abstraction for LLM inference with multiple backends
//

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.jeramo.meetingman", category: "nlp")

// MARK: - DTOs

/// Structured summary result from LLM
public struct SummaryResult: Codable, Equatable, Sendable {
    public let bullets: [String]
    public let decisions: [String]
    public let actionItems: [String]

    public init(bullets: [String], decisions: [String], actionItems: [String]) {
        self.bullets = bullets
        self.decisions = decisions
        self.actionItems = actionItems
    }

    /// Empty result
    public static var empty: SummaryResult {
        SummaryResult(bullets: [], decisions: [], actionItems: [])
    }

    /// Merge with another result
    public func merging(with other: SummaryResult) -> SummaryResult {
        SummaryResult(
            bullets: Array(Set(bullets + other.bullets)),
            decisions: Array(Set(decisions + other.decisions)),
            actionItems: Array(Set(actionItems + other.actionItems))
        )
    }
}

// MARK: - Protocol

/// Abstract LLM client for meeting summarization
public protocol LLMClient: Sendable {

    /// Summarize a complete transcript
    /// - Parameters:
    ///   - transcript: Full meeting transcript text
    ///   - maxBullets: Maximum number of summary bullets
    /// - Returns: Structured summary with bullets, decisions, action items
    func summarize(transcript: String, maxBullets: Int) async throws -> SummaryResult

    /// Refine existing summary with new transcript chunk
    /// - Parameters:
    ///   - context: Existing summary to refine
    ///   - newChunk: New transcript text to integrate
    /// - Returns: Updated summary
    func refine(context: SummaryResult, newChunk: String) async throws -> SummaryResult
}

// MARK: - Factory

/// Factory for creating appropriate LLM client based on availability
public enum LLMClientFactory {

    /// Create default client (Apple Intelligence only - iOS 26+)
    public static func makeDefault() -> LLMClient {
        AppleIntelligenceClient()
    }
}

// MARK: - Service Wrapper

/// High-level NLP service wrapping LLM client
public final class NLPService: Sendable {

    private let client: LLMClient

    public init(client: LLMClient? = nil) {
        self.client = client ?? LLMClientFactory.makeDefault()
    }

    /// Summarize transcript text
    public func summarize(transcript: String) async throws -> SummaryResult {
        guard !transcript.isEmpty else {
            throw LLMError.emptyTranscript
        }

        return try await client.summarize(transcript: transcript, maxBullets: 7)
    }

    /// Incrementally refine summary with new text
    public func refine(
        context: SummaryResult,
        newText: String
    ) async throws -> SummaryResult {
        guard !newText.isEmpty else { return context }

        return try await client.refine(context: context, newChunk: newText)
    }
}
