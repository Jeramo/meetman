//
//  LanguagePolicy.swift
//  MeetingCopilot
//
//  ASR language policy: choose initial locale and auto-switch to English if needed
//

import Foundation
import NaturalLanguage

/// Supported ASR locales
public enum ASRLocale: String, CaseIterable, Equatable, Sendable {
    case enUS = "en_US"
    case svSE = "sv_SE"
    case frFR = "fr_FR"
    case deDe = "de_DE"
    case esES = "es_ES"
    case itIT = "it_IT"
    case ptBR = "pt_BR"
    case jaJP = "ja_JP"
    case koKR = "ko_KR"
    case zhCN = "zh_CN"

    /// Convert to Locale for SFSpeechRecognizer
    public var locale: Locale {
        Locale(identifier: rawValue)
    }

    /// Human-readable display name
    public var displayName: String {
        switch self {
        case .enUS: return "English (US)"
        case .svSE: return "Swedish"
        case .frFR: return "French"
        case .deDe: return "German"
        case .esES: return "Spanish"
        case .itIT: return "Italian"
        case .ptBR: return "Portuguese (Brazil)"
        case .jaJP: return "Japanese"
        case .koKR: return "Korean"
        case .zhCN: return "Chinese (Simplified)"
        }
    }
}

/// ASR language policy for choosing and switching locales
public struct LanguagePolicy {

    /// Decide initial ASR locale from user override or device language.
    /// Default to English to avoid Swedish LM bias for English speakers.
    public static func initialASRLocale(
        userOverride: ASRLocale? = nil,
        device: Locale = .autoupdatingCurrent
    ) -> ASRLocale {
        // User override takes priority
        if let override = userOverride {
            return override
        }

        // Default to English to avoid Swedish bias
        // This prevents English speech from being transcribed as Swedish
        return .enUS
    }

    /// NaturalLanguage-based check to decide if we should switch to English.
    /// Trigger only when current recognizer is not en_US and English confidence is high.
    ///
    /// - Parameters:
    ///   - current: Current ASR locale
    ///   - partialText: Partial transcript text to analyze
    ///   - threshold: Confidence threshold (default 0.75)
    /// - Returns: True if should switch to English
    public static func shouldSwitchToEnglish(
        from current: ASRLocale,
        partialText: String,
        threshold: Double = 0.75
    ) -> Bool {
        // Don't switch if already English
        guard current != .enUS else { return false }

        // Need at least 8 characters for meaningful detection
        guard partialText.count >= 8 else { return false }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(partialText)

        guard let dominantLanguage = recognizer.dominantLanguage else {
            return false
        }

        // Get confidence for dominant language
        let hypotheses = recognizer.languageHypotheses(withMaximum: 1)
        let confidence = hypotheses[dominantLanguage] ?? 0.0

        // Switch if English detected with high confidence
        return dominantLanguage.rawValue == "en" && confidence >= threshold
    }
}
