//
//  AppleIntelligenceGate.swift
//  MeetingCopilot
//
//  Runtime check for Apple Intelligence availability and language support
//

#if canImport(FoundationModels)
import FoundationModels
#endif
import Foundation

@available(iOS 26, *)
struct AppleIntelligenceGate {
    enum Status {
        case available(outputLocale: String)          // OK to generate
        case unsupported(detected: String, fallback: String)
        case notAvailableOnDevice                     // feature disabled or framework missing
    }

    /// Pass the detected transcript language (BCP-47, e.g., "sv-SE").
    static func status(for detectedBCP47: String) -> Status {
        #if canImport(FoundationModels)
        // If the framework is present we still guard by supported matrix.
        if LLMLanguageSupport.isSupported(detectedBCP47) {
            return .available(outputLocale: LLMLanguageSupport.normalize(detectedBCP47))
        } else {
            return .unsupported(
                detected: LLMLanguageSupport.normalize(detectedBCP47),
                fallback: LLMLanguageSupport.suggestedFallback(for: detectedBCP47)
            )
        }
        #else
        return .notAvailableOnDevice
        #endif
    }
}
