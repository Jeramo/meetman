//
//  AudioRecorder.swift
//  MeetingCopilot
//
//  AVAudioEngine-based audio recorder with WAV output
//

@preconcurrency import AVFoundation
import OSLog

private let logger = Logger(subsystem: "com.jeramo.meetingman", category: "audio")

/// Audio buffer callback for streaming
public typealias AudioBufferCallback = @Sendable (AVAudioPCMBuffer) -> Void

/// Records audio to file and streams buffers for ASR
public final class AudioRecorder: @unchecked Sendable {

    private let engine = AVAudioEngine()
    private var wavWriter: WavFileWriter?
    private var bufferCallback: AudioBufferCallback?
    private let sessionManager = AudioSessionManager.shared

    public private(set) var isRecording = false
    public private(set) var outputURL: URL?

    public init() {}

    /// Start recording to file URL, calling bufferCallback for each audio buffer
    public func startRecording(
        to fileURL: URL,
        bufferCallback: @escaping AudioBufferCallback
    ) async throws {
        guard !isRecording else {
            logger.warning("startRecording called but already recording")
            return
        }

        logger.info("Starting audio recording to \(fileURL.lastPathComponent)")

        // Set flag immediately to prevent race condition
        isRecording = true

        do {
            // Check/request permission
            if !sessionManager.hasPermission {
                let granted = await sessionManager.requestPermission()
                guard granted else {
                    isRecording = false
                    throw AudioError.permissionDenied
                }
            }

            // Configure audio session
            try sessionManager.configureForRecording()

            self.outputURL = fileURL
            self.bufferCallback = bufferCallback

            // Setup audio engine
            try setupEngine()

            // Start engine
            try engine.start()
            logger.info("Recording started to \(fileURL.lastPathComponent)")
        } catch {
            // Roll back state on any failure
            isRecording = false
            self.bufferCallback = nil
            self.outputURL = nil
            logger.error("Failed to start audio engine: \(error.localizedDescription)")
            throw AudioError.recordingFailed(underlying: error)
        }
    }

    private func setupEngine() throws {
        // Ensure engine is stopped and clean
        if engine.isRunning {
            engine.stop()
        }

        let inputNode = engine.inputNode

        // Remove existing tap if present (safety check)
        // Note: removeTap doesn't throw if no tap exists
        inputNode.removeTap(onBus: 0)

        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Create recording format: mono 16kHz PCM16
        guard let recordingFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000,
            channels: 1,
            interleaved: true
        ) else {
            throw AudioError.invalidAudioFormat
        }

        // Create WAV writer
        guard let url = outputURL else {
            throw AudioError.fileWriteFailed
        }
        wavWriter = try WavFileWriter(
            fileURL: url,
            sampleRate: recordingFormat.sampleRate,
            channels: Int(recordingFormat.channelCount),
            bitDepth: 16
        )

        // Create converter if needed
        let converter: AVAudioConverter?
        if inputFormat != recordingFormat {
            converter = AVAudioConverter(from: inputFormat, to: recordingFormat)
        } else {
            converter = nil
        }

        // Install tap
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self else { return }

            // Convert if needed
            let finalBuffer: AVAudioPCMBuffer
            if let converter = converter {
                let frameCapacity = AVAudioFrameCount(
                    Double(buffer.frameLength) * recordingFormat.sampleRate / inputFormat.sampleRate
                )
                guard let convertedBuffer = AVAudioPCMBuffer(
                    pcmFormat: recordingFormat,
                    frameCapacity: frameCapacity
                ) else {
                    logger.error("Failed to create converted buffer")
                    return
                }

                var error: NSError?
                converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                    outStatus.pointee = .haveData
                    return buffer
                }

                if let error = error {
                    logger.error("Conversion error: \(error.localizedDescription)")
                    return
                }

                finalBuffer = convertedBuffer
            } else {
                finalBuffer = buffer
            }

            // Write to WAV file
            do {
                try self.wavWriter?.write(buffer: finalBuffer)
            } catch {
                logger.error("Failed to write WAV: \(error.localizedDescription)")
            }

            // Stream to callback
            self.bufferCallback?(finalBuffer)
        }

        logger.info("Audio engine configured: \(recordingFormat.sampleRate)Hz, \(recordingFormat.channelCount)ch")
    }

    /// Stop recording and finalize file
    public func stopRecording() throws {
        guard isRecording else {
            logger.warning("stopRecording called but not recording")
            return
        }

        logger.info("Stopping audio engine and removing tap")

        // Remove tap and stop engine
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        // Finalize WAV file
        try wavWriter?.finalize()
        wavWriter = nil

        // Clear state
        isRecording = false
        bufferCallback = nil
        outputURL = nil

        try sessionManager.deactivate()

        logger.info("Recording stopped successfully")
    }

    deinit {
        if isRecording {
            try? stopRecording()
        }
    }
}
