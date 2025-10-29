//
//  AppleIntelligenceClient.swift
//  MeetingCopilot
//
//  Apple Intelligence (Foundation Models) backend for LLM inference
//  iOS 26+ with FoundationModels framework - Guided Generation ONLY
//

#if canImport(FoundationModels)
import FoundationModels
#endif
import Foundation
import os

/// MeetingSummary struct using @Generable macro for guided generation
@available(iOS 26, *)
@Generable
public struct MeetingSummary: Codable {
    @Guide(description: "Concise bullet points summarizing key discussion topics")
    public var bullets: [String]

    @Guide(description: "Decisions made (past-tense commitments, agreements, approvals)")
    public var decisions: [String]

    @Guide(description: "Action items in format: 'Owner — Verb — Object [Due date if mentioned]'")
    public var actionItems: [String]

    public init(bullets: [String], decisions: [String], actionItems: [String]) {
        self.bullets = bullets
        self.decisions = decisions
        self.actionItems = actionItems
    }
}

/// LLM client using Apple's on-device Foundation Models (iOS 26+)
/// Uses guided generation to directly produce typed MeetingSummary values
public final class AppleIntelligenceClient: LLMClient {
    private let log = Logger(subsystem: "MeetingCopilot", category: "nlp")

    public init() {}

    public func summarize(transcript: String, maxBullets: Int) async throws -> SummaryResult {
        #if canImport(FoundationModels)
        guard #available(iOS 26, *) else {
            throw LLMError.notAvailable
        }

        // Session configured for on-device generation
        let session = LanguageModelSession()

        // Guided generation: ask the model to directly produce a typed MeetingSummary
        let prompt = PromptLibrary.summaryPrompt(transcript: transcript, maxBullets: maxBullets)

        do {
            let response = try await session.respond(
                to: prompt,
                generating: MeetingSummary.self
            )

            // Access the generated content
            let summary = response.content

            return SummaryResult(
                bullets: summary.bullets,
                decisions: summary.decisions,
                actionItems: summary.actionItems
            )
        } catch {
            log.error("Apple Intelligence summarization failed: \(error.localizedDescription)")
            throw LLMError.inferenceFailed(underlying: error)
        }
        #else
        throw LLMError.notAvailable
        #endif
    }

    public func refine(context: SummaryResult, newChunk: String) async throws -> SummaryResult {
        #if canImport(FoundationModels)
        guard #available(iOS 26, *) else {
            throw LLMError.notAvailable
        }

        let session = LanguageModelSession()
        let current = MeetingSummary(
            bullets: context.bullets,
            decisions: context.decisions,
            actionItems: context.actionItems
        )
        let prompt = PromptLibrary.refinementPrompt(context: current, newChunk: newChunk)

        do {
            let response = try await session.respond(
                to: prompt,
                generating: MeetingSummary.self
            )

            // Access the generated content
            let updated = response.content

            return SummaryResult(
                bullets: updated.bullets,
                decisions: updated.decisions,
                actionItems: updated.actionItems
            )
        } catch {
            log.error("Apple Intelligence refinement failed: \(error.localizedDescription)")
            throw LLMError.inferenceFailed(underlying: error)
        }
        #else
        throw LLMError.notAvailable
        #endif
    }
}
