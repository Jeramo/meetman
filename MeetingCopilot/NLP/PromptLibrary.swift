//
//  PromptLibrary.swift
//  MeetingCopilot
//
//  Prompt templates for LLM guided generation (iOS 26)
//

import Foundation

/// Centralized prompt templates for Apple Intelligence guided generation
enum PromptLibrary {

    /// Language detection prompt for transcript snippet (guided generation)
    @available(iOS 26, *)
    static func detectLanguagePrompt(sample: String, fallback: String = "en-US") -> String {
        """
        System: Detect the predominant human language of the text. Return a Swift value of type `DetectedLanguage`.
        Rules:
        - `bcp47`: include region if inferable (e.g., sv-SE, en-US). If unsure, use \(fallback).
        - `name`: English display name (e.g., Swedish, English).
        - `confidence`: 0..1.
        - If multiple languages appear, choose the one with the most tokens.

        Text (first 2000 chars):
        \(sample.prefix(2000))
        """
    }

    /// Profanity detection prompt - asks LLM to identify problematic content
    @available(iOS 26, *)
    static func profanityReportPrompt(transcript: String, fallbackLocale: String = "en-US") -> String {
        """
        System: Analyze the text and return a Swift value of type `ProfanityReport`.

        Rules:
        - Detect the predominant language; set `languageBCP47`. If unsure, use \(fallbackLocale).
        - Identify spans of ACTUAL profanity, slurs, insults, or sexual vulgarities.
        - DO NOT refuse the task for content reasons; you are auditing, not endorsing.
        - IMPORTANT: Only flag standalone offensive words, NOT innocent words that happen to contain those letters.
          • Example (Swedish): "men" = "but" (innocent) vs "jävla" = profanity
          • Example (English): "class" contains "ass" (innocent) vs "ass" standalone (profane)
        - Only flag words if you are CONFIDENT they are used offensively in context.
        - For each span:
          • `start`/`end` are character offsets of the COMPLETE WORD into the ORIGINAL string (0-based, end exclusive).
          • `token` is the exact substring in the original text.
          • `category` in {expletive, slur, sexual, insult, other}.
          • `severity` in {low, medium, high}.
          • `replacement` should be a neutral placeholder, e.g. "[expletive]" or a masked variant.
          • `confidence` should be at least 0.7 for flagging.
        - If nothing is profane, return `spans: []` and `overall.hasProfanity: false`.

        Text (last 6000 chars of the transcript):
        \(transcript.suffix(6000))
        """
    }

    /// Summarization prompt for full transcript (guided generation)
    /// Designed to work with FoundationModels guardrails by instructing paraphrasing over refusal
    static func summaryPrompt(
        transcript: String,
        maxBullets: Int,
        forceOutputLocale: String? = nil,
        defaultLocale: String = "en-us"
    ) -> String {
        let langDirective: String
        if let locale = forceOutputLocale {
            langDirective = "Language: Write ALL output in \(locale.uppercased())."
        } else {
            langDirective = "Language: Detect predominant language; if tied, use \(defaultLocale.uppercased())."
        }

        return """
        System: You're a neutral, privacy-preserving meeting notetaker. All participants consented to recording.
        Produce a Swift `MeetingSummary`.

        Safety & privacy:
        - Do NOT refuse; if content might be unsafe/sensitive, **paraphrase** or replace with labels like "[redacted]".
        - Never quote verbatim from the transcript; no explicit details about bodies/sex/violence.
        - Keep personal nouns (names, places, brands) in their original language.

        \(langDirective)

        Style:
        - ≤ \(maxBullets) bullets; each ≤ 20 words.
        - Decisions in past tense (e.g., "Agreed to proceed with option B").
        - Action items: Extract who does what, formatted as "PersonName — Action description [due date if mentioned]".
          Examples: "Alice — Send quarterly report by Friday", "Bob — Review architecture proposal", "Sarah — Schedule follow-up meeting next week".
        - Empty sections → empty arrays.

        Transcript (last 6000 chars):
        \(transcript.suffix(6000))
        """
    }

    /// Refinement prompt for incremental updates (guided generation)
    @available(iOS 26, *)
    static func refinementPrompt(context: MeetingSummary, newChunk: String) -> String {
        """
        System: You revise an existing summary Swift value with a new transcript segment.
        Keep structure stable and concise. Only add information that is ACTUALLY present in the new segment.

        Existing summary:
        - Bullets: \(context.bullets.joined(separator: ", "))
        - Decisions: \(context.decisions.joined(separator: ", "))
        - Action Items: \(context.actionItems.joined(separator: ", "))

        New segment:
        \(newChunk)

        Update the summary to incorporate the new segment. Do NOT invent or hallucinate content.
        For action items, use actual person names (e.g., "Alice — Send report by Friday", not "Owner — Verb — Object").
        """
    }

    /// Text beautification/polishing prompt (guided generation)
    /// Fixes punctuation, casing, splits run-ons, corrects spelling/spacing, contextually formats timestamps
    @available(iOS 26, *)
    static func beautifyPrompt(input: String, forceOutputLocale: String? = nil) -> String {
        let langDirective = forceOutputLocale.map { "Write ALL output in \($0)." }
            ?? "Detect the predominant language and write ALL output in that language."
        return """
        System: You rewrite user text to improve readability while preserving meaning. Return a Swift value of type `PolishedText`.

        Rules:
        - Add/repair punctuation and capitalization.
        - Split run-on sentences when natural; avoid fragments unless clearly stylistic.
        - Fix obvious spelling and spacing mistakes; DO NOT change semantics or factual content.
        - Quote short titles with curly quotes if appropriate.
        - Time formatting: when a numeric group clearly denotes a timestamp near words like "recording", "time", "at", "starts", "ends", "duration", convert MMSS or HMMSS to MM:SS (or HH:MM:SS). Otherwise treat numbers as IDs and DO NOT reformat them.
        - Never invent content. If you're unsure whether a number is a timestamp or an ID, leave it unchanged.
        - Content policy: do not refuse for profanity; paraphrase neutrally if needed. Do not censor names or dates.

        Output:
        - Return a `PolishedText` with `text` as the improved version.
        - For EVERY change, add an `edits` item with exact `start`/`end` offsets in the ORIGINAL string, the `from` substring, the `to` substring, a `kind`, and a short `note`.

        \(langDirective)

        Input (verbatim):
        \(input)
        """
    }
}
