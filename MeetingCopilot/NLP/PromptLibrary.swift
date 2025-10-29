//
//  PromptLibrary.swift
//  MeetingCopilot
//
//  Prompt templates for LLM guided generation (iOS 26)
//

import Foundation

/// Centralized prompt templates for Apple Intelligence guided generation
enum PromptLibrary {

    /// Summarization prompt for full transcript (guided generation)
    static func summaryPrompt(transcript: String, maxBullets: Int) -> String {
        """
        System: You are a precise meeting notetaker. Output ONLY the requested Swift type.
        Instructions:
        - Be concise and actionable.
        - Prefer past tense for decisions.
        - For action items, use "Owner — Verb — Object [Due]" text.

        Transcript (last 6000 chars):
        \(transcript.suffix(6000))

        Produce at most \(maxBullets) bullets.
        """
    }

    /// Refinement prompt for incremental updates (guided generation)
    @available(iOS 26, *)
    static func refinementPrompt(context: MeetingSummary, newChunk: String) -> String {
        """
        System: You revise an existing summary Swift value with a new transcript tail.
        Keep structure stable and concise.

        Existing summary:
        - Bullets: \(context.bullets.joined(separator: ", "))
        - Decisions: \(context.decisions.joined(separator: ", "))
        - Action Items: \(context.actionItems.joined(separator: ", "))

        New segment:
        \(newChunk)
        """
    }
}
