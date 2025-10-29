//
//  TextPolisher.swift
//  MeetingCopilot
//
//  Public API for text beautification using Apple Intelligence guided generation
//  Fixes punctuation, casing, splits run-ons, corrects spelling/spacing, contextually formats timestamps
//

#if canImport(FoundationModels)
import FoundationModels
#endif
import Foundation
import os

/// Text beautification service using Apple Intelligence (iOS 26+)
/// Provides a simple API to polish user text with a detailed edit trail
@available(iOS 26, *)
public enum TextPolisher {
    private static let log = Logger(subsystem: "MeetingCopilot", category: "text-polisher")

    /// Beautify/polish text using guided generation
    /// Returns a typed edit trail showing all transformations
    ///
    /// This method:
    /// - Fixes punctuation and capitalization
    /// - Splits run-on sentences naturally
    /// - Corrects obvious spelling and spacing mistakes
    /// - Contextually formats timestamps (e.g., "0005" → "00:05" when near time-related words)
    /// - Applies proper quote marks where appropriate
    /// - Preserves semantic meaning and factual content
    ///
    /// - Parameters:
    ///   - raw: The raw text to beautify
    ///   - locale: Optional BCP-47 locale to force output language (e.g., "en-US", "sv-SE").
    ///             If nil, the predominant language is auto-detected.
    ///   - temperature: Sampling temperature for generation (0.0 = deterministic, 1.0 = creative).
    ///                  Default is 0.1 for consistent beautification.
    ///   - timeout: Maximum time to wait for generation in seconds. Default is 10 seconds.
    /// - Returns: A `PolishedText` with improved text and a detailed edit trail
    /// - Throws: `LLMError` if generation fails or times out
    ///
    /// Example:
    /// ```swift
    /// let input = "the meeting starts 0005 and we need plan this through"
    /// let result = try await TextPolisher.beautify(input, locale: "en-US")
    /// print(result.text)  // "The meeting starts at 00:05, and we need to plan this through."
    /// print(result.edits.count)  // Number of changes made
    /// ```
    public static func beautify(
        _ raw: String,
        locale: String? = nil,
        temperature: Double = 0.1,
        timeout: TimeInterval = 10
    ) async throws -> PolishedText {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Early return for empty input
        guard !trimmed.isEmpty else {
            log.info("Empty input, returning empty result")
            return PolishedText(text: "", edits: [])
        }

        log.info("Beautifying text (\(trimmed.count) chars, locale: \(locale ?? "auto"))")

        // Generate the prompt with optional locale directive
        let prompt = PromptLibrary.beautifyPrompt(input: trimmed, forceOutputLocale: locale)

        // Use the shared language model hub for inference
        // This automatically handles timeout, cancellation, and error mapping
        let result: PolishedText = try await LanguageModelHub.shared.generate(
            prompt: prompt,
            as: PolishedText.self,
            temperature: temperature,
            timeout: timeout
        )

        log.info("Beautification complete: \(result.edits.count) edits made")
        log.debug("Edit summary: \(result.edits.map { "\($0.kind)" }.joined(separator: ", "))")

        return result
    }

    /// Convenience method to check if text needs beautification
    /// Returns true if the text appears to have issues that beautification could fix
    ///
    /// Note: This is a heuristic check and may not catch all issues.
    /// For authoritative results, call `beautify()` and check if `edits` is non-empty.
    ///
    /// - Parameter text: The text to check
    /// - Returns: True if the text likely needs beautification
    public static func needsBeautification(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        // Simple heuristics for common issues
        let hasLowercaseStart = trimmed.first?.isLowercase == true
        let hasMissingPunctuation = ![".", "!", "?"].contains(where: { trimmed.hasSuffix(String($0)) })
        let hasMultipleSpaces = trimmed.contains("  ")
        let hasNoSpacesAfterPunctuation = trimmed.range(of: "[.!?,][a-zA-Z]", options: .regularExpression) != nil
        let hasCommonSpellingPatterns = trimmed.range(of: "\\b(teh|wiht|adn|recieve)\\b", options: [.regularExpression, .caseInsensitive]) != nil

        return hasLowercaseStart
            || hasMissingPunctuation
            || hasMultipleSpaces
            || hasNoSpacesAfterPunctuation
            || hasCommonSpellingPatterns
    }
}
