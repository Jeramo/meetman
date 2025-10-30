//
//  PromptLibrary+SpeakerAware.swift
//  MeetingCopilot
//
//  Speaker-aware prompt generation for guided generation
//

import Foundation

extension PromptLibrary {

    /// Generate speaker-aware summary prompt with speaker-tagged transcript
    ///
    /// This prompt includes speaker labels (S1, S2, etc.) in the transcript
    /// and instructs the LLM to preserve attribution when helpful.
    ///
    /// - Parameters:
    ///   - labeledSegments: Array of transcript segments with speaker labels
    ///   - maxBullets: Maximum number of bullet points in summary
    ///   - forceOutputLocale: Optional locale to force output language
    ///   - defaultLocale: Default locale if language detection is inconclusive
    /// - Returns: Prompt string for guided generation
    @available(iOS 26, *)
    public static func speakerAwareSummary(
        labeledSegments: [LabeledSegment],
        maxBullets: Int,
        forceOutputLocale: String? = nil,
        defaultLocale: String = "en-us"
    ) -> String {
        // Format transcript with speaker tags
        let speakerTaggedTranscript = labeledSegments
            .map { "\($0.speakerID): \($0.text)" }
            .joined(separator: "\n")

        let langDirective: String
        if let locale = forceOutputLocale {
            langDirective = "Language: Write ALL output in \(locale.uppercased())."
        } else {
            langDirective = "Language: Detect predominant language; if tied, use \(defaultLocale.uppercased())."
        }

        return """
        System: You're a neutral, privacy-preserving meeting notetaker. All participants consented to recording.
        Produce a Swift `MeetingSummary` with speaker attribution when helpful.

        Safety & privacy:
        - Do NOT refuse; if content might be unsafe/sensitive, **paraphrase** or replace with labels like "[redacted]".
        - Never quote verbatim from the transcript; no explicit details about bodies/sex/violence.
        - Keep personal nouns (names, places, brands) in their original language.

        \(langDirective)

        Style:
        - ≤ \(maxBullets) bullets; each ≤ 20 words.
        - Decisions in past tense (e.g., "S2 agreed to proceed with option B" or "The team decided to proceed").
        - Action items: Extract who does what, formatted as "SpeakerID — Action description [due date if mentioned]".
          Examples: "S1 — Send quarterly report by Friday", "S2 — Review architecture proposal", "S3 — Schedule follow-up meeting next week".
        - Use speaker labels (S1, S2, etc.) when attribution adds clarity or accountability.
        - If unsure who spoke or attribution isn't helpful, omit the speaker ID.
        - Empty sections → empty arrays.

        Transcript with speaker tags:
        \(speakerTaggedTranscript.suffix(6000))
        """
    }

    /// Generate speaker statistics summary
    ///
    /// Creates a human-readable summary of speaker participation.
    ///
    /// - Parameters:
    ///   - segments: Array of labeled segments
    ///   - totalDuration: Total meeting duration in seconds
    /// - Returns: Formatted statistics string
    public static func speakerStatistics(
        segments: [LabeledSegment],
        totalDuration: TimeInterval
    ) -> String {
        let stats = Alignment.computeStatistics(segments)
        let sortedSpeakers = stats.keys.sorted()

        var lines: [String] = ["Speaker Statistics:"]

        for speakerID in sortedSpeakers {
            guard let (talkTime, wordCount) = stats[speakerID] else { continue }

            let percentage = totalDuration > 0 ? (talkTime / totalDuration) * 100 : 0
            let minutes = Int(talkTime / 60)
            let seconds = Int(talkTime.truncatingRemainder(dividingBy: 60))

            lines.append("""
            \(speakerID): \(minutes)m \(seconds)s (\(String(format: "%.1f", percentage))%), \(wordCount) words
            """)
        }

        return lines.joined(separator: "\n")
    }

    /// Generate speaker-aware refinement prompt
    ///
    /// Updates existing summary with new speaker-tagged content.
    ///
    /// - Parameters:
    ///   - context: Existing meeting summary
    ///   - newSegments: New labeled segments to incorporate
    /// - Returns: Refinement prompt
    @available(iOS 26, *)
    public static func speakerAwareRefinement(
        context: MeetingSummary,
        newSegments: [LabeledSegment]
    ) -> String {
        let newContent = newSegments
            .map { "\($0.speakerID): \($0.text)" }
            .joined(separator: "\n")

        return """
        System: You revise an existing summary Swift value with new speaker-tagged transcript segments.
        Keep structure stable and concise. Only add information that is ACTUALLY present in the new segments.
        Preserve or add speaker attribution (S1, S2, etc.) when it improves clarity or accountability.

        Existing summary:
        - Bullets: \(context.bullets.joined(separator: ", "))
        - Decisions: \(context.decisions.joined(separator: ", "))
        - Action Items: \(context.actionItems.joined(separator: ", "))

        New speaker-tagged segments:
        \(newContent)

        Update the summary to incorporate the new segments. Do NOT invent or hallucinate content.
        For action items, use speaker IDs (e.g., "S1 — Send report by Friday") unless actual names are mentioned.
        """
    }

    /// Format labeled segments for display in UI
    ///
    /// - Parameters:
    ///   - segments: Array of labeled segments
    ///   - includeTimestamps: Whether to include timestamps (default: false)
    /// - Returns: Formatted string suitable for display
    public static func formatTranscriptWithSpeakers(
        _ segments: [LabeledSegment],
        includeTimestamps: Bool = false
    ) -> String {
        if includeTimestamps {
            return segments.map { segment in
                let timestamp = formatTimestamp(segment.start)
                return "[\(timestamp)] \(segment.speakerID): \(segment.text)"
            }.joined(separator: "\n\n")
        } else {
            return segments.map { segment in
                "\(segment.speakerID): \(segment.text)"
            }.joined(separator: "\n\n")
        }
    }

    // MARK: - Private Helpers

    /// Format timestamp as MM:SS or HH:MM:SS
    private static func formatTimestamp(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
}
