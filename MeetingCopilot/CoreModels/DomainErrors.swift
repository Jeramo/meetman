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
    case unsupportedLanguage(language: String, supportedLanguages: [String])

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
        case .unsupportedLanguage(let lang, let supported):
            let supportedList = supported.prefix(5).joined(separator: ", ")
            let more = supported.count > 5 ? " and \(supported.count - 5) more" : ""
            return "Language '\(lang)' is not yet supported by Apple Intelligence. Supported languages: \(supportedList)\(more). Change your device language to English in Settings → General → Language & Region."
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
