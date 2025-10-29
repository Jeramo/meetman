//
//  DetectedLanguage.swift
//  MeetingCopilot
//
//  Language detection result using guided generation (iOS 26)
//

#if canImport(FoundationModels)
import FoundationModels
#endif
import Foundation

/// Language detection result using @Generable macro for guided generation
@available(iOS 26, *)
@Generable
public struct DetectedLanguage: Codable, Sendable {
    @Guide(description: "BCP-47 language tag with region if inferable (e.g., sv-SE, en-US)")
    public let bcp47: String

    @Guide(description: "English display name of the language (e.g., Swedish, English)")
    public let name: String

    @Guide(description: "Confidence score between 0.0 (low) and 1.0 (high)")
    public let confidence: Double

    public init(bcp47: String, name: String, confidence: Double) {
        self.bcp47 = bcp47
        self.name = name
        self.confidence = confidence
    }
}
