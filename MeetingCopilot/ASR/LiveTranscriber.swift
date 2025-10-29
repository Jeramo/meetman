//
//  LiveTranscriber.swift
//  MeetingCopilot
//
//  Streaming speech recognition using SFSpeechRecognizer
//

import Foundation
import Speech
import AVFoundation
import OSLog

private let logger = Logger(subsystem: "com.jeramo.meetingman", category: "asr")

/// Callback for transcript segments
public typealias TranscriptCallback = @Sendable (TranscriptChunkData) -> Void

/// Live speech-to-text transcriber using SFSpeechRecognizer
public final class LiveTranscriber: @unchecked Sendable {

    private let recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    private var chunkIndex = 0
    private var startTime = Date()
    private var lastResultTime: TimeInterval = 0
    private var lastPartialResult: (text: String, time: TimeInterval)?
    private var currentMeetingID: UUID?
    private var currentCallback: TranscriptCallback?
    private var isStopping = false

    public private(set) var isTranscribing = false

    public init(locale: Locale = .current) {
        self.recognizer = SFSpeechRecognizer(locale: locale)
        logger.info("Initialized transcriber with locale: \(locale.identifier)")
    }

    /// Check if speech recognition is available
    public var isAvailable: Bool {
        recognizer?.isAvailable ?? false
    }

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

    /// Start transcription, calling callback for each segment
    public func start(
        meetingID: UUID,
        onSegment: @escaping TranscriptCallback
    ) async throws {
        guard !isTranscribing else {
            logger.warning("Already transcribing")
            return
        }

        guard let recognizer = recognizer else {
            logger.error("No recognizer available")
            throw ASRError.notAvailable
        }

        logger.info("Recognizer available: \(recognizer.isAvailable)")
        guard recognizer.isAvailable else {
            logger.error("Recognizer not available")
            throw ASRError.notAvailable
        }

        // Check authorization
        let status = SFSpeechRecognizer.authorizationStatus()
        logger.info("Speech recognition status: \(String(describing: status))")
        guard status == .authorized else {
            logger.error("Speech recognition not authorized")
            throw ASRError.permissionDenied
        }

        // Reset state
        chunkIndex = 0
        startTime = Date()
        lastResultTime = 0
        lastPartialResult = nil
        currentMeetingID = meetingID
        currentCallback = onSegment
        isStopping = false

        // Create recognition request
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = false // Allow cloud fallback for better reliability

        recognitionRequest = request

        // Start recognition task
        logger.info("Creating recognition task...")
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else {
                logger.warning("Recognition callback called but self is nil")
                return
            }

            logger.debug("Recognition callback invoked")

            // Ignore callbacks after stop() has been called
            guard !self.isStopping else {
                logger.debug("Ignoring recognition callback after stop")
                return
            }

            if let error = error {
                logger.error("Recognition error: \(error.localizedDescription)")
                return
            }

            guard let result = result else {
                logger.warning("Recognition callback with no result and no error")
                return
            }

            let currentTime = Date().timeIntervalSince(self.startTime)
            let text = result.bestTranscription.formattedString

            // Log all results for debugging
            logger.info("Recognition result (final=\(result.isFinal)): \(text)")

            if result.isFinal {
                // Emit final result
                let chunk = TranscriptChunkData(
                    meetingID: meetingID,
                    index: self.chunkIndex,
                    text: text,
                    startTime: self.lastResultTime,
                    endTime: currentTime,
                    isFinal: true
                )

                logger.info("Final transcript chunk #\(self.chunkIndex): \(chunk.text)")

                onSegment(chunk)

                self.chunkIndex += 1
                self.lastResultTime = currentTime
                self.lastPartialResult = nil // Clear partial since we got final
            } else {
                // Track partial result in case we need it when stopping
                self.lastPartialResult = (text: text, time: currentTime)

                // Also emit partial result for live transcript display
                let partialChunk = TranscriptChunkData(
                    meetingID: meetingID,
                    index: self.chunkIndex,
                    text: text,
                    startTime: self.lastResultTime,
                    endTime: currentTime,
                    isFinal: false
                )

                onSegment(partialChunk)
            }
        }

        logger.info("Recognition task created, state: \(String(describing: self.recognitionTask?.state))")
        isTranscribing = true
        logger.info("Transcription started")
    }

    /// Append audio buffer for recognition
    public func append(buffer: AVAudioPCMBuffer) {
        guard let request = recognitionRequest else {
            logger.warning("Attempted to append buffer without active recognition request")
            return
        }
        request.append(buffer)
        logger.debug("Appended buffer: \(buffer.frameLength) frames")
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

        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        recognitionRequest = nil
        recognitionTask = nil
        lastPartialResult = nil
        currentMeetingID = nil
        currentCallback = nil
        isTranscribing = false

        logger.info("Transcription stopped after \(self.chunkIndex) chunks")
    }

    deinit {
        stop()
    }
}
