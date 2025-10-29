//
//  HeuristicSummarizer.swift
//  MeetingCopilot
//
//  Pure Swift heuristic-based summarizer (no AI dependencies)
//  Deterministic and testable fallback implementation
//

import Foundation
import NaturalLanguage
import OSLog

private let logger = Logger(subsystem: "com.jeramo.meetingman", category: "nlp")

/// Heuristic-based summarizer using NaturalLanguage framework
/// Deterministic, testable, and requires no external APIs
public final class HeuristicSummarizer: LLMClient, @unchecked Sendable {

    private let sentenceTokenizer = NLTokenizer(unit: .sentence)
    private let wordTokenizer = NLTokenizer(unit: .word)

    public init() {
        logger.info("Initialized heuristic summarizer")
    }

    public func summarize(transcript: String, maxBullets: Int) async throws -> SummaryResult {
        guard !transcript.isEmpty else {
            throw LLMError.emptyTranscript
        }

        logger.info("Summarizing transcript: \(transcript.count) chars")

        // Extract components
        let bullets = extractBullets(from: transcript, maxCount: maxBullets)
        let decisions = extractDecisions(from: transcript)
        let actionItems = extractActionItems(from: transcript)

        let result = SummaryResult(
            bullets: bullets,
            decisions: decisions,
            actionItems: actionItems
        )

        logger.info("Summary: \(bullets.count) bullets, \(decisions.count) decisions, \(actionItems.count) actions")
        return result
    }

    public func refine(context: SummaryResult, newChunk: String) async throws -> SummaryResult {
        guard !newChunk.isEmpty else { return context }

        logger.info("Refining summary with new chunk: \(newChunk.count) chars")

        // Extract new components
        let newBullets = extractBullets(from: newChunk, maxCount: 3)
        let newDecisions = extractDecisions(from: newChunk)
        let newActionItems = extractActionItems(from: newChunk)

        // Merge with deduplication
        let mergedBullets = deduplicate(context.bullets + newBullets).prefix(7)
        let mergedDecisions = deduplicate(context.decisions + newDecisions)
        let mergedActions = deduplicate(context.actionItems + newActionItems)

        return SummaryResult(
            bullets: Array(mergedBullets),
            decisions: Array(mergedDecisions),
            actionItems: Array(mergedActions)
        )
    }

    // MARK: - Bullet Extraction

    private func extractBullets(from text: String, maxCount: Int) -> [String] {
        // Split into sentences
        let sentences = tokenizeSentences(text)
        guard !sentences.isEmpty else { return [] }

        // Score sentences by importance
        let scored = sentences.map { sentence in
            (sentence: sentence, score: scoreSentence(sentence, in: text))
        }

        // Take top N by score
        let topSentences = scored
            .sorted { $0.score > $1.score }
            .prefix(maxCount)
            .map { $0.sentence }

        // Clean up
        return topSentences.map { cleanSentence($0) }
    }

    private func scoreSentence(_ sentence: String, in fullText: String) -> Double {
        var score = 0.0

        let words = tokenizeWords(sentence)
        guard !words.isEmpty else { return 0.0 }

        // Prefer sentences with important keywords
        let importantKeywords = ["decided", "agreed", "discussed", "reviewed", "action", "next", "important", "key", "main", "focus"]
        let lowercased = sentence.lowercased()
        for keyword in importantKeywords {
            if lowercased.contains(keyword) {
                score += 2.0
            }
        }

        // Prefer sentences with proper nouns (names, places)
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = sentence
        tagger.enumerateTags(in: sentence.startIndex..<sentence.endIndex, unit: .word, scheme: .nameType) { tag, _ in
            if tag != nil {
                score += 1.0
            }
            return true
        }

        // Penalize very short or very long sentences
        let wordCount = words.count
        if wordCount < 5 || wordCount > 30 {
            score -= 1.0
        }

        // Prefer sentences with nouns and verbs
        score += Double(words.count) * 0.1

        return score
    }

    // MARK: - Decision Extraction

    private func extractDecisions(from text: String) -> [String] {
        var decisions: [String] = []

        let sentences = tokenizeSentences(text)

        // Decision trigger patterns
        let decisionPatterns = [
            "decided to",
            "agreed to",
            "agreed that",
            "chose to",
            "approved",
            "committed to",
            "will move forward",
            "concluded that",
            "determined that"
        ]

        for sentence in sentences {
            let lowercased = sentence.lowercased()

            // Check if sentence contains decision trigger
            for pattern in decisionPatterns {
                if lowercased.contains(pattern) {
                    decisions.append(cleanSentence(sentence))
                    break
                }
            }
        }

        return Array(Set(decisions)) // Deduplicate
    }

    // MARK: - Action Item Extraction

    private func extractActionItems(from text: String) -> [String] {
        var actions: [String] = []

        let sentences = tokenizeSentences(text)

        // Action item patterns with regex
        let patterns = [
            // "John will review the document"
            #"([A-Z][a-z]+)\s+(?:will|should|needs to|must)\s+([a-z]+(?:\s+[a-z]+){0,5})"#,

            // "We need to schedule a meeting"
            #"(?:we|team)\s+(?:need to|should|will|must)\s+([a-z]+(?:\s+[a-z]+){0,5})"#,

            // "Action: Review the proposal"
            #"[Aa]ction\s*:\s*(.+?)(?:\.|$)"#,

            // "TODO: Update documentation"
            #"[Tt][Oo][Dd][Oo]\s*:\s*(.+?)(?:\.|$)"#
        ]

        for sentence in sentences {
            for patternString in patterns {
                if let regex = try? NSRegularExpression(pattern: patternString, options: []) {
                    let range = NSRange(sentence.startIndex..<sentence.endIndex, in: sentence)
                    let matches = regex.matches(in: sentence, options: [], range: range)

                    for match in matches {
                        // Extract captured groups
                        if match.numberOfRanges > 1,
                           let range = Range(match.range(at: 1), in: sentence) {
                            let action = String(sentence[range])
                            actions.append(cleanSentence(action))
                        }
                    }
                }
            }
        }

        // Also look for imperative sentences (starts with verb)
        let imperatives = extractImperatives(from: sentences)
        actions.append(contentsOf: imperatives)

        return Array(Set(actions)) // Deduplicate
    }

    private func extractImperatives(from sentences: [String]) -> [String] {
        var imperatives: [String] = []

        let tagger = NLTagger(tagSchemes: [.lexicalClass])

        for sentence in sentences {
            let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count > 10, trimmed.count < 100 else { continue }

            tagger.string = trimmed

            // Check if first word is a verb
            let firstWordRange = trimmed.startIndex..<(trimmed.firstIndex(of: " ") ?? trimmed.endIndex)
            let tags = tagger.tags(in: firstWordRange, unit: .word, scheme: .lexicalClass)

            if let firstTag = tags.first?.0, firstTag == .verb {
                imperatives.append(cleanSentence(trimmed))
            }
        }

        return imperatives
    }

    // MARK: - Utilities

    private func tokenizeSentences(_ text: String) -> [String] {
        var sentences: [String] = []

        sentenceTokenizer.string = text
        sentenceTokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = String(text[range])
            sentences.append(sentence)
            return true
        }

        return sentences
    }

    private func tokenizeWords(_ text: String) -> [String] {
        var words: [String] = []

        wordTokenizer.string = text
        wordTokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let word = String(text[range])
            words.append(word)
            return true
        }

        return words
    }

    private func cleanSentence(_ sentence: String) -> String {
        sentence
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private func deduplicate(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.filter { item in
            let normalized = item.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if seen.contains(normalized) {
                return false
            }
            seen.insert(normalized)
            return true
        }
    }
}
