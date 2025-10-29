//
//  AudioSession.swift
//  MeetingCopilot
//
//  Audio session configuration and lifecycle management
//

import AVFoundation
import OSLog

private let logger = Logger(subsystem: "com.jeramo.meetingman", category: "audio")

/// Manages AVAudioSession configuration for recording
public final class AudioSessionManager: @unchecked Sendable {

    public static let shared = AudioSessionManager()

    private let session = AVAudioSession.sharedInstance()

    private init() {}

    /// Configure audio session for recording
    public func configureForRecording() throws {
        logger.info("Configuring audio session for recording")

        do {
            try session.setCategory(.record, mode: .measurement, options: [])
            try session.setActive(true, options: [])

            // Request 16kHz sample rate for optimal ASR performance
            try session.setPreferredSampleRate(16000)

            // Prefer mono input
            try session.setPreferredInputNumberOfChannels(1)

            logger.info("Audio session configured: sampleRate=\(self.session.sampleRate), channels=\(self.session.inputNumberOfChannels)")
        } catch {
            logger.error("Failed to configure audio session: \(error.localizedDescription)")
            throw AudioError.sessionSetupFailed
        }
    }

    /// Configure audio session for playback
    public func configureForPlayback() throws {
        logger.info("Configuring audio session for playback")

        do {
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true, options: [])

            logger.info("Audio session configured for playback")
        } catch {
            logger.error("Failed to configure audio session for playback: \(error.localizedDescription)")
            throw AudioError.sessionSetupFailed
        }
    }

    /// Deactivate audio session
    public func deactivate() throws {
        logger.info("Deactivating audio session")
        do {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            logger.warning("Failed to deactivate audio session: \(error.localizedDescription)")
            throw AudioError.sessionSetupFailed
        }
    }

    /// Check microphone permission status (returns true if granted)
    public var hasPermission: Bool {
        return AVAudioApplication.shared.recordPermission == .granted
    }

    /// Request microphone permission
    public func requestPermission() async -> Bool {
        logger.info("Requesting microphone permission")

        return await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                logger.info("Microphone permission: \(granted ? "granted" : "denied")")
                continuation.resume(returning: granted)
            }
        }
    }

    /// Current sample rate
    public var sampleRate: Double {
        session.sampleRate
    }

    /// Current input channels
    public var inputChannels: Int {
        session.inputNumberOfChannels
    }
}
