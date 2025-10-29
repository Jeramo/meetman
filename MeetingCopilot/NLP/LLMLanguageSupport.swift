//
//  LLMLanguageSupport.swift
//  MeetingCopilot
//
//  Runtime gate for Apple Intelligence language coverage.
//  NOTE: Keep this list in sync with Apple's public matrix.
//

import Foundation

/// Runtime gate for Apple Intelligence language coverage.
/// NOTE: Keep this list in sync with Apple's public matrix.
/// Prefer BCP-47 tags; accept language-only fallbacks.
enum LLMLanguageSupport {
    // Known-available today (example set; update as Apple expands)
    // Use lowercase for normalization.
    private static let supportedBCP47: Set<String> = [
        "en-us", "en-gb", "en-au",
        "fr-fr", "fr-ca",
        "de-de",
        "it-it",
        "pt-br",
        "es-es", "es-us", "es-419",
        "zh-hans",   // Simplified Chinese
        "ja-jp",
        "ko-kr"
    ]

    /// Normalize to lowercase and standard separators.
    static func normalize(_ bcp47: String) -> String {
        bcp47
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
    }

    /// Returns true if the exact tag or its base language is covered.
    static func isSupported(_ bcp47: String) -> Bool {
        let tag = normalize(bcp47)
        if supportedBCP47.contains(tag) { return true }
        let base = tag.split(separator: "-").first.map(String.init) ?? tag
        if supportedBCP47.contains(base) { return true }
        // Any entry that starts with "<base>-"
        return supportedBCP47.contains(where: { $0.hasPrefix(base + "-") })
    }

    /// Suggest a sensible fallback for a given unsupported tag.
    /// For Romance/Germanic families, favor nearest; otherwise default to en-US.
    static func suggestedFallback(for bcp47: String) -> String {
        let tag = normalize(bcp47)
        let base = tag.split(separator: "-").first.map(String.init) ?? tag
        switch base {
        case "pt": return "pt-br"
        case "es": return "es-es"
        case "fr": return "fr-fr"
        case "de": return "de-de"
        case "it": return "it-it"
        case "nl", "da", "no", "sv": return "en-gb"   // Northern Europe → English (GB)
        case "zh": return "zh-hans"
        default: return "en-us"
        }
    }
}
