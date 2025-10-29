//
//  LanguageDetector.swift
//  MeetingCopilot
//
//  Dual-approach language detection: Foundation Models (iOS 26) + NaturalLanguage fallback
//

#if canImport(FoundationModels)
import FoundationModels
#endif
import Foundation
import NaturalLanguage
import OSLog

private let logger = Logger(subsystem: "MeetingCopilot", category: "nlp")

/// Language detection result
public struct LanguageDetectionResult: Sendable {
    public let bcp47: String
    public let name: String?
    public let confidence: Double
    public let method: DetectionMethod

    public enum DetectionMethod: String, Sendable {
        case foundationModels = "Foundation Models"
        case naturalLanguage = "NaturalLanguage"
        case fallback = "Default"
    }

    public init(bcp47: String, name: String? = nil, confidence: Double, method: DetectionMethod) {
        self.bcp47 = bcp47
        self.name = name
        self.confidence = confidence
        self.method = method
    }
}

/// Language detector with Foundation Models + NaturalLanguage fallback
public actor LanguageDetector {
    public static let shared = LanguageDetector()

    private init() {}

    /// Detect language using Foundation Models (iOS 26+) with NaturalLanguage fallback
    /// - Parameter text: Text to analyze (first 2000 chars will be used)
    /// - Returns: Detection result with BCP-47 tag, optional name, and confidence
    public func detect(_ text: String) async -> LanguageDetectionResult {
        guard !text.isEmpty else {
            return LanguageDetectionResult(bcp47: "en-US", name: "English", confidence: 0.0, method: .fallback)
        }

        // Try Foundation Models first (iOS 26+)
        if #available(iOS 26, *) {
            if let fmResult = try? await detectWithFoundationModels(text) {
                logger.info("Language detected via Foundation Models: \(fmResult.bcp47) (\(fmResult.name ?? "unknown")) at \(fmResult.confidence)")
                return fmResult
            }
        }

        // Fall back to NaturalLanguage
        if let nlResult = detectWithNaturalLanguage(text) {
            logger.info("Language detected via NaturalLanguage: \(nlResult.bcp47) at \(nlResult.confidence)")
            return nlResult
        }

        // Last resort default
        logger.warning("Language detection failed, using default en-US")
        return LanguageDetectionResult(bcp47: "en-US", name: "English", confidence: 0.0, method: .fallback)
    }

    // MARK: - Foundation Models Detection (iOS 26+)

    @available(iOS 26, *)
    private func detectWithFoundationModels(_ text: String) async throws -> LanguageDetectionResult {
        #if canImport(FoundationModels)
        let prompt = PromptLibrary.detectLanguagePrompt(sample: text, fallback: "en-US")

        // Use LanguageModelHub with permissive guardrails
        let detected: DetectedLanguage = try await LanguageModelHub.shared.generate(
            prompt: prompt,
            as: DetectedLanguage.self,
            temperature: 0.0,  // Classification = deterministic
            timeout: 8
        )

        // Normalize BCP-47 tag (lowercase, use "-" not "_")
        let normalized = detected.bcp47
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()

        return LanguageDetectionResult(
            bcp47: normalized,
            name: detected.name,
            confidence: detected.confidence,
            method: .foundationModels
        )
        #else
        throw LLMError.notAvailable
        #endif
    }

    // MARK: - NaturalLanguage Fallback

    private func detectWithNaturalLanguage(_ text: String) -> LanguageDetectionResult? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)

        guard let dominantLanguage = recognizer.dominantLanguage else {
            return nil
        }

        // Get confidence from language hypotheses
        let hypotheses = recognizer.languageHypotheses(withMaximum: 1)
        let confidence = hypotheses[dominantLanguage] ?? 0.0

        // NaturalLanguage returns ISO 639-1 codes (e.g., "sv", "en")
        // Map to BCP-47 with region if possible
        let bcp47 = mapToFullBCP47(dominantLanguage.rawValue)

        return LanguageDetectionResult(
            bcp47: bcp47,
            name: nil,  // NaturalLanguage doesn't provide display names
            confidence: confidence,
            method: .naturalLanguage
        )
    }

    /// Map ISO 639-1 code to BCP-47 with region
    /// Falls back to base code if region is unknown
    private func mapToFullBCP47(_ iso639: String) -> String {
        switch iso639.lowercased() {
        case "sv": return "sv-SE"  // Swedish → Sweden
        case "en": return "en-US"  // English → US (common default)
        case "fr": return "fr-FR"  // French → France
        case "de": return "de-DE"  // German → Germany
        case "es": return "es-ES"  // Spanish → Spain
        case "it": return "it-IT"  // Italian → Italy
        case "pt": return "pt-BR"  // Portuguese → Brazil (most common)
        case "ja": return "ja-JP"  // Japanese → Japan
        case "ko": return "ko-KR"  // Korean → Korea
        case "zh": return "zh-Hans" // Chinese → Simplified
        case "nb", "no": return "nb-NO"  // Norwegian → Norway
        case "da": return "da-DK"  // Danish → Denmark
        case "nl": return "nl-NL"  // Dutch → Netherlands
        case "fi": return "fi-FI"  // Finnish → Finland
        default: return iso639  // Return base code if no mapping
        }
    }
}
