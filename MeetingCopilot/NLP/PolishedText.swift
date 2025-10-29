//
//  PolishedText.swift
//  MeetingCopilot
//
//  Typed output for text beautification/polishing using guided generation
//  Provides a detailed edit trail for all transformations
//

#if canImport(FoundationModels)
import FoundationModels
#endif
import Foundation

/// Result of text beautification with a detailed edit trail
/// Used with Apple Intelligence guided generation to produce type-safe output
@available(iOS 26, *)
@Generable
public struct PolishedText: Codable, Sendable {
    @Guide(description: "The improved, polished version of the input text")
    public let text: String

    @Guide(description: "List of every change made, with exact offsets in the ORIGINAL input")
    public let edits: [Edit]

    @Generable
    public struct Edit: Codable, Sendable {
        /// 0-based character offset in the ORIGINAL input where change starts
        @Guide(description: "Character offset where the change begins in the ORIGINAL text (0-based)")
        public let start: Int

        /// 0-based character offset in the ORIGINAL input where change ends (exclusive)
        @Guide(description: "Character offset where the change ends in the ORIGINAL text (0-based, exclusive)")
        public let end: Int

        /// Classification of the type of change made
        @Guide(description: "Type of change: punctuation, capitalization, sentenceSplit, spelling, spacing, timeFormat, quoteStyle, or other")
        public let kind: String

        /// The original substring from the input
        @Guide(description: "The original text that was changed")
        public let from: String

        /// The replacement substring in the output
        @Guide(description: "The replacement text in the polished version")
        public let to: String

        /// Brief explanation of why this change was made
        @Guide(description: "Short explanation of the reason for this change")
        public let note: String

        public init(start: Int, end: Int, kind: String, from: String, to: String, note: String) {
            self.start = start
            self.end = end
            self.kind = kind
            self.from = from
            self.to = to
            self.note = note
        }
    }

    // MARK: - Edit Kind Constants

    /// Common edit kind values for convenience
    public enum EditKind {
        public static let punctuation = "punctuation"      // Added/fixed punctuation
        public static let capitalization = "capitalization"   // Fixed letter casing
        public static let sentenceSplit = "sentenceSplit"    // Split run-on into multiple sentences
        public static let spelling = "spelling"         // Corrected spelling mistake
        public static let spacing = "spacing"          // Fixed spacing issues
        public static let timeFormat = "timeFormat"       // Converted numeric timestamp (e.g., 0005 → 00:05)
        public static let quoteStyle = "quoteStyle"       // Applied proper quote marks
        public static let other = "other"            // Other improvements
    }

    public init(text: String, edits: [Edit]) {
        self.text = text
        self.edits = edits
    }
}
