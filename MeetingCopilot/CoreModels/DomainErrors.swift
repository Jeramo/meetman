//
//  DomainErrors.swift
//  MeetingCopilot
//
//  Domain-specific error types
//

import Foundation

/// Audio recording errors
public enum AudioError: Error, LocalizedError {
    case permissionDenied
    case sessionSetupFailed
    case recordingFailed(underlying: Error)
    case invalidAudioFormat
    case fileWriteFailed

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone permission denied"
        case .sessionSetupFailed:
            return "Failed to setup audio session"
        case .recordingFailed(let error):
            return "Recording failed: \(error.localizedDescription)"
        case .invalidAudioFormat:
            return "Invalid audio format"
        case .fileWriteFailed:
            return "Failed to write audio file"
        }
    }
}

/// Speech recognition errors
public enum ASRError: Error, LocalizedError {
    case permissionDenied
    case notAvailable
    case recognitionFailed(underlying: Error)
    case invalidAudioBuffer
    case timeout

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Speech recognition permission denied"
        case .notAvailable:
            return "Speech recognition not available"
        case .recognitionFailed(let error):
            return "Recognition failed: \(error.localizedDescription)"
        case .invalidAudioBuffer:
            return "Invalid audio buffer"
        case .timeout:
            return "Recognition timeout"
        }
    }
}

/// NLP/summarization errors
public enum LLMError: Error, LocalizedError {
    case notAvailable
    case badJSON
    case inferenceFailed(underlying: Error)
    case canceled
    case emptyTranscript
    case transcriptTooShort(characters: Int, minimum: Int)
    case unsupportedLanguage(language: String, supportedLanguages: [String])
    case modelNotReady
    case appleIntelligenceNotEnabled
    case deviceNotEligible

    public var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "AI model not available"
        case .badJSON:
            return "Invalid JSON response from model"
        case .inferenceFailed(let error):
            return "Inference failed: \(error.localizedDescription)"
        case .canceled:
            return "Operation canceled"
        case .emptyTranscript:
            return "Cannot summarize empty transcript"
        case .transcriptTooShort(let chars, let minimum):
            return "Recording too short to generate summary. Need at least \(minimum) characters (~1 minute), got \(chars) characters."
        case .unsupportedLanguage(let lang, let supported):
            let supportedList = supported.prefix(5).joined(separator: ", ")
            let more = supported.count > 5 ? " and \(supported.count - 5) more" : ""
            return "Language '\(lang)' is not yet supported by Apple Intelligence. Supported languages: \(supportedList)\(more). Change your device language to English in Settings → General → Language & Region."
        case .modelNotReady:
            return "Apple Intelligence models are still downloading. Please wait a few minutes and try again. Check download progress in Settings → Apple Intelligence & Siri."
        case .appleIntelligenceNotEnabled:
            return "Apple Intelligence is not enabled on this device. Enable it in Settings → Apple Intelligence & Siri."
        case .deviceNotEligible:
            return "This device is not eligible for Apple Intelligence. Apple Intelligence requires iPhone 15 Pro or later, iPad with M1 or later, or Mac with Apple Silicon."
        }
    }
}

/// Persistence errors
public enum PersistenceError: Error, LocalizedError {
    case saveFailed(underlying: Error)
    case fetchFailed(underlying: Error)
    case deleteFailed(underlying: Error)
    case migrationFailed
    case invalidData

    public var errorDescription: String? {
        switch self {
        case .saveFailed(let error):
            return "Save failed: \(error.localizedDescription)"
        case .fetchFailed(let error):
            return "Fetch failed: \(error.localizedDescription)"
        case .deleteFailed(let error):
            return "Delete failed: \(error.localizedDescription)"
        case .migrationFailed:
            return "Data migration failed"
        case .invalidData:
            return "Invalid data"
        }
    }
}

/// EventKit integration errors
public enum ActionsError: Error, LocalizedError {
    case remindersPermissionDenied
    case calendarPermissionDenied
    case creationFailed(underlying: Error)
    case noDefaultCalendar
    case noDefaultReminderList

    public var errorDescription: String? {
        switch self {
        case .remindersPermissionDenied:
            return "Reminders permission denied"
        case .calendarPermissionDenied:
            return "Calendar permission denied"
        case .creationFailed(let error):
            return "Creation failed: \(error.localizedDescription)"
        case .noDefaultCalendar:
            return "No default calendar found"
        case .noDefaultReminderList:
            return "No default reminder list found"
        }
    }
}

/// Export errors
public enum ExportError: Error, LocalizedError {
    case encodingFailed
    case fileWriteFailed
    case invalidFormat

    public var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode data"
        case .fileWriteFailed:
            return "Failed to write file"
        case .invalidFormat:
            return "Invalid export format"
        }
    }
}
