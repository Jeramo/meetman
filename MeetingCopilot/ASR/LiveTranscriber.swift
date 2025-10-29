//
//  LiveTranscriber.swift
//  MeetingCopilot
//
//  Streaming speech recognition with auto-locale switching
//

import Foundation
import Speech
import AVFoundation
import NaturalLanguage
import OSLog

private let logger = Logger(subsystem: "com.jeramo.meetingman", category: "asr")

// MARK: - ASR Language Policy (inlined)

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

// MARK: - Live Transcriber

/// Callback for transcript segments
public typealias TranscriptCallback = @Sendable (TranscriptChunkData) -> Void

/// Notification for ASR partial results (used after locale restart)
extension Notification.Name {
    public static let asrPartial = Notification.Name("asrPartial")
}

/// Live speech-to-text transcriber with auto-locale switching
public final class LiveTranscriber: @unchecked Sendable {

    // MARK: - State

    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    private(set) var currentLocale: ASRLocale = .enUS
    private var hasSwitchedLocale = false

    private var chunkIndex = 0
    private var startTime = Date()
    private var lastResultTime: TimeInterval = 0
    private var lastPartialResult: (text: String, time: TimeInterval)?
    private var currentMeetingID: UUID?
    private var currentCallback: TranscriptCallback?
    private var isStopping = false

    public private(set) var isTranscribing = false

    // MARK: - Initialization

    public init() {
        logger.info("LiveTranscriber initialized (locale will be set on start)")
    }

    // MARK: - Authorization

    /// Request speech recognition authorization
    public static func requestAuthorization() async -> Bool {
        logger.info("Requesting speech recognition authorization")

        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                let granted = status == .authorized
                logger.info("Speech recognition authorization: \(granted ? "granted" : "denied")")
                continuation.resume(returning: granted)
            }
        }
    }

    // MARK: - Transcription Control

    /// Start transcription with specified locale.
    /// Idempotent: stops any existing task before starting a new one.
    /// Note: Does NOT install audio tap - buffers must be fed via append(buffer:)
    ///
    /// - Parameters:
    ///   - locale: ASR locale to use
    ///   - meetingID: Meeting identifier
    ///   - onSegment: Callback for transcript segments
    public func start(
        locale: ASRLocale,
        meetingID: UUID,
        onSegment: @escaping TranscriptCallback
    ) throws {
        logger.info("LiveTranscriber.start() called with locale: \(locale.rawValue)")

        // Idempotent: stop any existing task
        if isTranscribing {
            logger.warning("Transcriber already running, stopping first")
            stop()
        }

        self.currentLocale = locale
        self.currentMeetingID = meetingID
        self.currentCallback = onSegment

        logger.info("Initializing SFSpeechRecognizer with locale: \(self.currentLocale.rawValue, privacy: .public)")

        recognizer = SFSpeechRecognizer(locale: currentLocale.locale)
        recognizer?.defaultTaskHint = .dictation

        guard let recognizer = recognizer, recognizer.isAvailable else {
            logger.error("Recognizer not available for locale: \(self.currentLocale.rawValue)")
            throw ASRError.notAvailable
        }

        // Check authorization
        let status = SFSpeechRecognizer.authorizationStatus()
        guard status == .authorized else {
            logger.error("Speech recognition not authorized")
            throw ASRError.permissionDenied
        }

        // Reset state
        chunkIndex = 0
        startTime = Date()
        lastResultTime = 0
        lastPartialResult = nil
        isStopping = false
        hasSwitchedLocale = false

        // Create recognition request
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.requiresOnDeviceRecognition = true
        req.shouldReportPartialResults = true
        self.request = req

        // Start recognition task
        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }

            // Ignore callbacks after stop() has been called
            guard !self.isStopping else {
                logger.debug("Ignoring recognition callback after stop")
                return
            }

            if let error = error {
                logger.error("ASR error: \(String(describing: error), privacy: .public)")
                return
            }

            guard let result = result else {
                logger.warning("Recognition callback with no result and no error")
                return
            }

            let currentTime = Date().timeIntervalSince(self.startTime)
            let text = result.bestTranscription.formattedString

            logger.debug("Recognition result (final=\(result.isFinal)): \(text.prefix(50))...")

            // Early auto-switch to English (once only)
            if !self.hasSwitchedLocale,
               LanguagePolicy.shouldSwitchToEnglish(from: self.currentLocale, partialText: text) {
                logger.info("Auto-switching ASR locale to en_US based on NL detection")
                self.hasSwitchedLocale = true
                Task { @MainActor in
                    await self.restartRecognition(with: .enUS)
                }
                return // Don't emit this partial, we're restarting
            }

            if result.isFinal {
                // Emit final result
                guard let meetingID = self.currentMeetingID, let callback = self.currentCallback else {
                    return
                }

                let chunk = TranscriptChunkData(
                    meetingID: meetingID,
                    index: self.chunkIndex,
                    text: text,
                    startTime: self.lastResultTime,
                    endTime: currentTime,
                    isFinal: true
                )

                logger.info("Final transcript chunk #\(self.chunkIndex): \(chunk.text)")

                callback(chunk)

                self.chunkIndex += 1
                self.lastResultTime = currentTime
                self.lastPartialResult = nil
            } else {
                // Check if this is a NEW utterance (text got shorter or completely different)
                // This happens when user pauses and ASR starts a fresh recognition
                if let lastPartial = self.lastPartialResult,
                   !lastPartial.text.isEmpty,
                   text.count < Int(Double(lastPartial.text.count) * 0.8) { // Text shrank significantly

                    // Finalize the previous partial as a complete chunk
                    logger.info("Detected new utterance (text shrink: \(lastPartial.text.count) → \(text.count)), finalizing previous chunk")

                    guard let meetingID = self.currentMeetingID, let callback = self.currentCallback else {
                        return
                    }

                    let finalChunk = TranscriptChunkData(
                        meetingID: meetingID,
                        index: self.chunkIndex,
                        text: lastPartial.text,
                        startTime: self.lastResultTime,
                        endTime: lastPartial.time,
                        isFinal: true
                    )

                    logger.info("Auto-finalized chunk #\(self.chunkIndex): \(finalChunk.text)")
                    callback(finalChunk)

                    // Move to next chunk
                    self.chunkIndex += 1
                    self.lastResultTime = currentTime
                }

                // Track partial result
                self.lastPartialResult = (text: text, time: currentTime)

                // Emit partial result for live display
                guard let meetingID = self.currentMeetingID, let callback = self.currentCallback else {
                    return
                }

                let partialChunk = TranscriptChunkData(
                    meetingID: meetingID,
                    index: self.chunkIndex,
                    text: text,
                    startTime: self.lastResultTime,
                    endTime: currentTime,
                    isFinal: false
                )

                callback(partialChunk)
            }
        }

        isTranscribing = true
        logger.info("Transcription started with locale: \(self.currentLocale.rawValue)")
    }

    /// Append audio buffer for recognition
    public func append(buffer: AVAudioPCMBuffer) {
        guard let request = request else {
            logger.warning("Attempted to append buffer without active recognition request")
            return
        }
        request.append(buffer)
    }

    /// Stop transcription
    public func stop() {
        guard isTranscribing else { return }

        // Set flag to ignore further callbacks
        isStopping = true

        // Emit last partial result as final if we have one
        if let partial = lastPartialResult,
           let meetingID = currentMeetingID,
           let callback = currentCallback,
           !partial.text.isEmpty {

            let chunk = TranscriptChunkData(
                meetingID: meetingID,
                index: self.chunkIndex,
                text: partial.text,
                startTime: self.lastResultTime,
                endTime: partial.time,
                isFinal: true
            )

            logger.info("Emitting last partial result as final chunk #\(self.chunkIndex): \(chunk.text)")
            callback(chunk)
            self.chunkIndex += 1
        }

        task?.finish()
        task?.cancel()
        request?.endAudio()

        task = nil
        request = nil
        recognizer = nil
        lastPartialResult = nil
        currentMeetingID = nil
        currentCallback = nil
        isTranscribing = false
        hasSwitchedLocale = false

        logger.info("Transcription stopped after \(self.chunkIndex) chunks")
    }

    // MARK: - Private Helpers

    /// Restart recognition with a new locale (single-switch path).
    /// Replaces recognizer+request+task while keeping audio buffer flow.
    @MainActor
    private func restartRecognition(with newLocale: ASRLocale) async {
        logger.info("Restarting recognition with locale: \(newLocale.rawValue)")

        // Cancel current task
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        recognizer = nil

        // Update locale
        currentLocale = newLocale
        recognizer = SFSpeechRecognizer(locale: newLocale.locale)
        recognizer?.defaultTaskHint = .dictation

        guard let recognizer = recognizer, recognizer.isAvailable else {
            logger.error("Recognizer not available after switch to: \(newLocale.rawValue)")
            return
        }

        // Create new request
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.requiresOnDeviceRecognition = true
        req.shouldReportPartialResults = true
        request = req

        // Start new task (buffers continue to flow via append())
        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }

            guard !self.isStopping else {
                logger.debug("Ignoring recognition callback after stop (post-switch)")
                return
            }

            if let error = error {
                logger.error("ASR error (after switch): \(String(describing: error), privacy: .public)")
                return
            }

            guard let result = result else {
                logger.warning("Recognition callback with no result (after switch)")
                return
            }

            let currentTime = Date().timeIntervalSince(self.startTime)
            let text = result.bestTranscription.formattedString

            logger.debug("Recognition result (post-switch, final=\(result.isFinal)): \(text.prefix(50))...")

            if result.isFinal {
                guard let meetingID = self.currentMeetingID, let callback = self.currentCallback else {
                    return
                }

                let chunk = TranscriptChunkData(
                    meetingID: meetingID,
                    index: self.chunkIndex,
                    text: text,
                    startTime: self.lastResultTime,
                    endTime: currentTime,
                    isFinal: true
                )

                logger.info("Final transcript chunk #\(self.chunkIndex) (post-switch): \(chunk.text)")

                callback(chunk)

                self.chunkIndex += 1
                self.lastResultTime = currentTime
                self.lastPartialResult = nil
            } else {
                // Check if this is a NEW utterance (text got shorter or completely different)
                if let lastPartial = self.lastPartialResult,
                   !lastPartial.text.isEmpty,
                   text.count < Int(Double(lastPartial.text.count) * 0.8) {

                    logger.info("Detected new utterance (post-switch): \(lastPartial.text.count) → \(text.count), finalizing")

                    guard let meetingID = self.currentMeetingID, let callback = self.currentCallback else {
                        return
                    }

                    let finalChunk = TranscriptChunkData(
                        meetingID: meetingID,
                        index: self.chunkIndex,
                        text: lastPartial.text,
                        startTime: self.lastResultTime,
                        endTime: lastPartial.time,
                        isFinal: true
                    )

                    logger.info("Auto-finalized chunk #\(self.chunkIndex) (post-switch): \(finalChunk.text)")
                    callback(finalChunk)

                    self.chunkIndex += 1
                    self.lastResultTime = currentTime
                }

                self.lastPartialResult = (text: text, time: currentTime)

                guard let meetingID = self.currentMeetingID, let callback = self.currentCallback else {
                    return
                }

                let partialChunk = TranscriptChunkData(
                    meetingID: meetingID,
                    index: self.chunkIndex,
                    text: text,
                    startTime: self.lastResultTime,
                    endTime: currentTime,
                    isFinal: false
                )

                callback(partialChunk)
            }
        }

        logger.info("Recognition restarted with locale: \(newLocale.rawValue)")
    }

    deinit {
        stop()
    }
}
