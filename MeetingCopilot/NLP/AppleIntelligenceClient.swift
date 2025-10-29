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

// MARK: - Sensitive Content Sanitizer

/// Sanitizes sensitive content in transcripts before LLM inference
/// Covers profanity, bodily functions, sexual terms, violence, slurs
/// to reduce FoundationModels guardrail false positives
struct ProfanitySanitizer {

    /// Sanitization mode
    enum Mode {
        case redact  // Replace with "[redacted]"
        case mask    // Replace with "s*t" style masking
    }

    // MARK: - Category-based word lists (Swedish + English)

    /// Bodily functions and bathroom references
    private static let bodily: [String] = [
        // Swedish
        "toalett", "toaletten", "bajsa", "kissa", "kiss", "skita",
        "pissa", "runk", "onanera", "gå på toaletten",
        // English
        "toilet", "bathroom", "pee", "poop", "crap", "piss", "shit",
        "urinate", "defecate", "masturbate", "go to the bathroom"
    ]

    /// Sexual terms and explicit content
    private static let sexual: [String] = [
        // Swedish
        "sex", "knulla", "porr", "naken", "fitta", "kuk", "penis",
        "vagina", "bröst", "rumpa", "sexig", "hora", "fittor",
        // English
        "fuck", "fucking", "sex", "porn", "naked", "nude", "cock",
        "dick", "pussy", "cunt", "boobs", "ass", "sexy", "whore", "slut"
    ]

    /// Violence and threats
    private static let violence: [String] = [
        // Swedish
        "döda", "mörda", "skada", "hot", "våld", "slå", "skjut",
        // English
        "kill", "murder", "hurt", "threat", "violence", "beat", "shoot",
        "stab", "dead", "die", "attack"
    ]

    /// Slurs and derogatory terms
    private static let slurs: [String] = [
        // Swedish
        "idiot", "cp", "mongo", "bögjävel", "bög", "kärring",
        // English
        "idiot", "retard", "retarded", "fag", "faggot", "bitch",
        "bastard", "asshole", "nigger", "nigga"
    ]

    /// Profanity (general expletives)
    private static let profanity: [String] = [
        // Swedish
        "fan", "jävla", "jävlar", "helvete", "skit",
        // English
        "damn", "hell", "bastard"
    ]

    /// Sanitize text by redacting sensitive content
    /// - Parameters:
    ///   - text: Text to sanitize
    ///   - mode: Redaction mode
    ///   - aggressive: If true, redact all categories; if false, only profanity/slurs
    static func sanitize(_ text: String, mode: Mode = .redact, aggressive: Bool = false) -> String {
        var output = text

        // Select categories based on aggressiveness
        let categories: [[String]] = aggressive
            ? [bodily, sexual, violence, slurs, profanity]  // All categories
            : [slurs, profanity]                             // Only offensive language

        // Build unified pattern
        let allWords = categories.flatMap { $0 }
        guard !allWords.isEmpty else { return text }

        let patterns = allWords
            .sorted { $0.count > $1.count }  // Match longer words first
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: "|")

        guard let regex = try? NSRegularExpression(
            pattern: "\\b(\(patterns))\\b",
            options: [.caseInsensitive]
        ) else {
            return text
        }

        let replacer: (String) -> String = { word in
            switch mode {
            case .redact:
                return "[redacted]"
            case .mask:
                guard word.count > 2 else { return "[redacted]" }
                let first = word.prefix(1)
                let last = word.suffix(1)
                let stars = String(repeating: "*", count: max(1, word.count - 2))
                return "\(first)\(stars)\(last)"
            }
        }

        let nsString = output as NSString
        let matches = regex.matches(in: output, range: NSRange(location: 0, length: nsString.length))

        for match in matches.reversed() {
            let matchedWord = nsString.substring(with: match.range)
            let replacement = replacer(matchedWord)
            output = (output as NSString).replacingCharacters(in: match.range, with: replacement)
        }

        return output
    }

    /// Check if text contains any sensitive content
    static func containsProfanity(_ text: String) -> Bool {
        let allWords = [bodily, sexual, violence, slurs, profanity].flatMap { $0 }
        let patterns = allWords
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: "|")

        guard let regex = try? NSRegularExpression(
            pattern: "\\b(\(patterns))\\b",
            options: [.caseInsensitive]
        ) else {
            return false
        }

        let range = NSRange(location: 0, length: text.utf16.count)
        return regex.firstMatch(in: text, range: range) != nil
    }
}

// MARK: - Meeting Summary

/// MeetingSummary struct using @Generable macro for guided generation
@available(iOS 26, *)
@Generable
public struct MeetingSummary: Codable, Sendable {
    @Guide(description: "Concise bullet points summarizing key discussion topics")
    public var bullets: [String]

    @Guide(description: "Decisions made (past-tense commitments, agreements, approvals)")
    public var decisions: [String]

    @Guide(description: "Action items with actual person names: 'PersonName — Action description [due date if mentioned]'. Examples: 'Alice — Send report by Friday', 'Bob — Review proposal'")
    public var actionItems: [String]

    public init(bullets: [String], decisions: [String], actionItems: [String]) {
        self.bullets = bullets
        self.decisions = decisions
        self.actionItems = actionItems
    }
}

// MARK: - Profanity Report

/// LLM-generated report identifying profanity spans with metadata
@available(iOS 26, *)
@Generable
public struct ProfanityReport: Codable, Sendable {
    public let languageBCP47: String         // e.g. "sv-SE", "en-US"
    public let spans: [Span]                 // zero or more flagged items
    public let overall: Overall

    @Generable
    public struct Span: Codable, Sendable {
        public let start: Int                // character offset in original string (0-based)
        public let end: Int                  // exclusive end offset
        public let token: String             // exact substring that was flagged
        public let category: String          // classification: "expletive", "slur", "sexual", "insult", "other"
        public let severity: String          // how severe: "low", "medium", "high"
        public let replacement: String       // suggested sanitized form
        public let confidence: Double        // 0.0 to 1.0 confidence in this detection

        public init(start: Int, end: Int, token: String, category: String, severity: String, replacement: String, confidence: Double) {
            self.start = start
            self.end = end
            self.token = token
            self.category = category
            self.severity = severity
            self.replacement = replacement
            self.confidence = confidence
        }
    }

    @Generable
    public struct Overall: Codable, Sendable {
        public let hasProfanity: Bool
        public let maxSeverity: String       // "low", "medium", or "high"
        public let confidence: Double

        public init(hasProfanity: Bool, maxSeverity: String, confidence: Double) {
            self.hasProfanity = hasProfanity
            self.maxSeverity = maxSeverity
            self.confidence = confidence
        }
    }

    public init(languageBCP47: String, spans: [Span], overall: Overall) {
        self.languageBCP47 = languageBCP47
        self.spans = spans
        self.overall = overall
    }
}

/// LLM client using Apple's on-device Foundation Models (iOS 26+)
/// Uses guided generation to directly produce typed MeetingSummary values
/// Implements sanitize-and-retry to handle content safety rejections
public final class AppleIntelligenceClient: LLMClient {
    private let log = Logger(subsystem: "MeetingCopilot", category: "nlp")

    public init() {}

    public func summarize(transcript: String, maxBullets: Int, forceOutputLocale: String?) async throws -> SummaryResult {
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMError.emptyTranscript
        }

        #if canImport(FoundationModels)
        guard #available(iOS 26, *) else {
            throw LLMError.notAvailable
        }

        // Using permissive guardrails allows processing of unsupported languages
        // The model can read Swedish (or other languages) and output in the requested locale
        log.info("Using guided generation with permissive guardrails")
        #endif

        // Level 1: Try with raw transcript
        do {
            return try await summarizeOnce(transcript: transcript, maxBullets: maxBullets, forceOutputLocale: forceOutputLocale)
        } catch {
            log.warning("Initial summarization failed: \(error.localizedDescription)")

            guard case LLMError.inferenceFailed = error else {
                throw error  // Re-throw if it's not a content safety issue
            }

            // Level 2: Try with basic profanity sanitization
            do {
                let sanitized = ProfanitySanitizer.sanitize(transcript, mode: .redact, aggressive: false)
                log.info("Retrying with basic sanitization (profanity redacted)")
                log.debug("Sanitized preview (level 2): \(sanitized.prefix(200))...")
                return try await summarizeOnce(transcript: sanitized, maxBullets: maxBullets, forceOutputLocale: forceOutputLocale)
            } catch {
                log.warning("Basic sanitization retry failed: \(error.localizedDescription)")

                guard case LLMError.inferenceFailed = error else {
                    throw error
                }

                // Level 3: Try with aggressive sanitization
                let aggressivelySanitized = ProfanitySanitizer.sanitize(transcript, mode: .redact, aggressive: true)
                log.info("Retrying with aggressive sanitization (also replacing potentially flagged words)")
                log.debug("Sanitized preview (level 3): \(aggressivelySanitized.prefix(200))...")

                do {
                    return try await summarizeOnce(transcript: aggressivelySanitized, maxBullets: maxBullets, forceOutputLocale: forceOutputLocale)
                } catch {
                    // All retries failed - save feedback attachment for Apple
                    log.error("All sanitization attempts failed, generating feedback attachment")
                    await saveFeedbackAttachment(
                        transcript: transcript,
                        error: error
                    )
                    throw error
                }
            }
        }
    }

    /// Save a feedback attachment when guardrails trigger on seemingly innocent content
    private func saveFeedbackAttachment(transcript: String, error: Error) async {
        #if canImport(FoundationModels)
        guard #available(iOS 26, *) else { return }

        // Only generate feedback for guardrail violations
        guard case LLMError.inferenceFailed = error else { return }

        let preview = String(transcript.prefix(300))

        // Note: FoundationModels feedback API types are not fully documented
        // For now, log the information that would go into the feedback
        log.error("Guardrail triggered on potentially innocent content")
        log.error("Transcript preview: \(preview)")
        log.error("Please file feedback at https://feedbackassistant.apple.com with:")
        log.error("- Component: FoundationModels")
        log.error("- Issue: Unexpected guardrail on neutral Swedish meeting transcript")
        log.error("- Expected: A neutral MeetingSummary with bullets, decisions, action items")

        // TODO: Uncomment when FoundationModels feedback API is stable/documented
        // let data = await LanguageModelHub.shared.feedbackAttachment(...)
        // try? data.write(to: url)
        #endif
    }

    /// Internal method to perform a single summarization attempt
    private func summarizeOnce(transcript: String, maxBullets: Int, forceOutputLocale: String?) async throws -> SummaryResult {
        #if canImport(FoundationModels)
        guard #available(iOS 26, *) else {
            throw LLMError.notAvailable
        }

        // Generate summary prompt with optional forced output locale
        let prompt = PromptLibrary.summaryPrompt(
            transcript: transcript,
            maxBullets: maxBullets,
            forceOutputLocale: forceOutputLocale
        )

        log.debug("Transcript length: \(transcript.count) chars")
        log.debug("Transcript preview: \(transcript.prefix(200))...")

        let summary: MeetingSummary = try await LanguageModelHub.shared.generate(
            prompt: prompt,
            as: MeetingSummary.self,
            temperature: 0.2,
            timeout: 15
        )

        log.info("Generated summary: \(summary.bullets.count) bullets, \(summary.decisions.count) decisions, \(summary.actionItems.count) actions")

        return SummaryResult(
            bullets: summary.bullets,
            decisions: summary.decisions,
            actionItems: summary.actionItems
        )
        #else
        throw LLMError.notAvailable
        #endif
    }

    public func refine(context: SummaryResult, newChunk: String) async throws -> SummaryResult {
        guard !newChunk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return context
        }

        // Level 1: Try with raw chunk first
        do {
            return try await refineOnce(context: context, newChunk: newChunk)
        } catch {
            log.warning("Initial refinement failed: \(error.localizedDescription)")

            guard case LLMError.inferenceFailed = error else {
                throw error  // Re-throw if it's not a content safety issue
            }

            // Level 2: Try with basic profanity sanitization
            do {
                let sanitized = ProfanitySanitizer.sanitize(newChunk, mode: .redact, aggressive: false)
                log.info("Retrying refinement with basic sanitization (profanity redacted)")
                return try await refineOnce(context: context, newChunk: sanitized)
            } catch {
                log.warning("Basic sanitization retry failed: \(error.localizedDescription)")

                guard case LLMError.inferenceFailed = error else {
                    throw error
                }

                // Level 3: Try with aggressive sanitization
                let aggressivelySanitized = ProfanitySanitizer.sanitize(newChunk, mode: .redact, aggressive: true)
                log.info("Retrying refinement with aggressive sanitization")
                return try await refineOnce(context: context, newChunk: aggressivelySanitized)
            }
        }
    }

    /// Internal method to perform a single refinement attempt
    private func refineOnce(context: SummaryResult, newChunk: String) async throws -> SummaryResult {
        #if canImport(FoundationModels)
        guard #available(iOS 26, *) else {
            throw LLMError.notAvailable
        }

        let current = MeetingSummary(
            bullets: context.bullets,
            decisions: context.decisions,
            actionItems: context.actionItems
        )
        let prompt = PromptLibrary.refinementPrompt(context: current, newChunk: newChunk)

        let updated = try await LanguageModelHub.shared.generate(
            prompt: prompt,
            as: MeetingSummary.self
        )

        return SummaryResult(
            bullets: updated.bullets,
            decisions: updated.decisions,
            actionItems: updated.actionItems
        )
        #else
        throw LLMError.notAvailable
        #endif
    }

    // MARK: - LLM-Guided Profanity Detection and Sanitization

    /// End-to-end helper: Ask LLM to detect profanity, apply replacements, then summarize
    /// This is superior to static word lists because the LLM knows what triggers its own safety filters
    public func summarizeWithLLMRedaction(
        transcript: String,
        maxBullets: Int
    ) async throws -> (report: ProfanityReport, result: SummaryResult, sanitized: String) {
        #if canImport(FoundationModels)
        guard #available(iOS 26, *) else {
            throw LLMError.notAvailable
        }

        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw LLMError.emptyTranscript
        }

        // 1) Ask the model to identify profanity spans
        log.info("Requesting profanity analysis from LLM")
        let reportPrompt = PromptLibrary.profanityReportPrompt(transcript: trimmed)
        let report: ProfanityReport = try await LanguageModelHub.shared.generate(
            prompt: reportPrompt,
            as: ProfanityReport.self,
            temperature: 0.0,     // classification → deterministic
            timeout: 8
        )

        log.info("Profanity analysis complete: \(report.spans.count) spans detected, hasProfanity: \(report.overall.hasProfanity)")

        // 2) Apply replacements deterministically (no regex; trust the LLM's indices)
        var sanitized = applyReplacementsByIndex(in: trimmed, spans: report.spans)

        if report.overall.hasProfanity {
            log.debug("Sanitized transcript preview: \(sanitized.prefix(200))...")
        }

        // 3) Try to summarize with LLM-sanitized text, fall back to aggressive if still blocked
        do {
            let snippet = sanitized.prefix(1500).description
            let langPrompt = PromptLibrary.detectLanguagePrompt(sample: snippet)
            let detected: DetectedLanguage = try await LanguageModelHub.shared.generate(
                prompt: langPrompt,
                as: DetectedLanguage.self,
                temperature: 0.0,
                timeout: 5
            )

            log.info("Detected language: \(detected.bcp47) (confidence: \(detected.confidence))")

            let sumPrompt = PromptLibrary.summaryPrompt(
                transcript: sanitized,
                maxBullets: maxBullets,
                defaultLocale: detected.bcp47
            )

            let summary: MeetingSummary = try await LanguageModelHub.shared.generate(
                prompt: sumPrompt,
                as: MeetingSummary.self,
                temperature: 0.2,
                timeout: 15
            )

            log.info("Generated summary: \(summary.bullets.count) bullets, \(summary.decisions.count) decisions, \(summary.actionItems.count) actions")

            return (
                report,
                SummaryResult(
                    bullets: summary.bullets,
                    decisions: summary.decisions,
                    actionItems: summary.actionItems
                ),
                sanitized
            )
        } catch {
            // LLM-guided sanitization still triggered filters - fall back to aggressive mode
            log.warning("LLM-sanitized text still blocked, trying aggressive sanitization: \(error.localizedDescription)")

            guard case LLMError.inferenceFailed = error else {
                throw error
            }

            // Apply aggressive sanitization to the original transcript
            sanitized = ProfanitySanitizer.sanitize(trimmed, mode: .redact, aggressive: true)
            log.info("Retrying with aggressive sanitization (static word list)")

            let snippet = sanitized.prefix(1500).description
            let langPrompt = PromptLibrary.detectLanguagePrompt(sample: snippet)
            let detected: DetectedLanguage = try await LanguageModelHub.shared.generate(
                prompt: langPrompt,
                as: DetectedLanguage.self,
                temperature: 0.0,
                timeout: 5
            )

            log.info("Detected language: \(detected.bcp47) (confidence: \(detected.confidence))")

            let sumPrompt = PromptLibrary.summaryPrompt(
                transcript: sanitized,
                maxBullets: maxBullets,
                defaultLocale: detected.bcp47
            )

            let summary: MeetingSummary = try await LanguageModelHub.shared.generate(
                prompt: sumPrompt,
                as: MeetingSummary.self,
                temperature: 0.2,
                timeout: 15
            )

            log.info("Generated summary with aggressive sanitization: \(summary.bullets.count) bullets, \(summary.decisions.count) decisions, \(summary.actionItems.count) actions")

            return (
                report,
                SummaryResult(
                    bullets: summary.bullets,
                    decisions: summary.decisions,
                    actionItems: summary.actionItems
                ),
                sanitized
            )
        }
        #else
        throw LLMError.notAvailable
        #endif
    }

    /// Replace substrings using 0-based character offsets from the ORIGINAL string
    /// Important: Swift String is grapheme-cluster based, so we walk by characters
    private func applyReplacementsByIndex(in text: String, spans: [ProfanityReport.Span]) -> String {
        guard !spans.isEmpty else { return text }

        var characters = Array(text)

        // Apply from right to left so indices remain valid
        for span in spans.sorted(by: { $0.start > $1.start }) {
            guard span.start >= 0,
                  span.end <= characters.count,
                  span.start < span.end else {
                log.warning("Invalid span indices: start=\(span.start), end=\(span.end), length=\(characters.count)")
                continue
            }

            let replacementChars = Array(span.replacement)
            characters.replaceSubrange(span.start..<span.end, with: replacementChars)

            log.debug("Replaced '\(span.token)' (\(span.category), \(span.severity)) with '\(span.replacement)'")
        }

        return String(characters)
    }
}
