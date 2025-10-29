//
//  MeetingVM.swift
//  MeetingCopilot
//
//  ViewModel for meeting capture orchestration
//

import Foundation
import SwiftUI
@preconcurrency import SwiftData
import Observation
@preconcurrency import AVFoundation
import OSLog

private let logger = Logger(subsystem: "com.jeramo.meetingman", category: "ui")

/// Observable view model for meeting capture
@MainActor
@Observable
public final class MeetingVM {

    // MARK: - State

    public var meeting: Meeting?
    public var isRecording = false
    public var elapsedTime: TimeInterval = 0
    public var liveTranscript: String = ""
    public var errorMessage: String?

    // MARK: - Dependencies

    @ObservationIgnored private let audioRecorder = AudioRecorder()
    @ObservationIgnored private let transcriber = LiveTranscriber()
    @ObservationIgnored private let assembler = TranscriptAssembler()

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var audioURL: URL?

    // Computed repositories
    private var context: ModelContext {
        Store.shared.mainContext
    }

    private var meetingRepo: MeetingRepository {
        MeetingRepository(context: context)
    }

    private var transcriptRepo: TranscriptRepository {
        TranscriptRepository(context: context)
    }

    private var decisionRepo: DecisionRepository {
        DecisionRepository(context: context)
    }

    // MARK: - Actions

    /// Start recording new meeting
    public func startCapture(title: String?, attendees: [PersonRef] = []) async throws {
        guard !isRecording else { return }

        logger.info("Starting meeting capture")

        // Request speech recognition authorization
        let speechAuthGranted = await LiveTranscriber.requestAuthorization()
        guard speechAuthGranted else {
            logger.error("Speech recognition permission denied")
            throw ASRError.permissionDenied
        }

        // Create meeting record
        let meetingTitle = title ?? "Meeting \(Date().formatted(date: .abbreviated, time: .shortened))"
        meeting = try meetingRepo.create(title: meetingTitle, attendees: attendees)

        guard let meeting = meeting else {
            throw PersistenceError.saveFailed(underlying: NSError(domain: "MeetingVM", code: -1))
        }

        // Setup audio file URL
        let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        audioURL = docsURL.appendingPathComponent("meeting_\(meeting.id.uuidString).wav")

        // Start audio recording
        try await audioRecorder.startRecording(to: audioURL!) { [weak self] buffer in
            guard let self = self else { return }

            logger.debug("Received audio buffer: \(buffer.frameLength) frames")

            // Stream to transcriber (buffer is read-only, safe to pass)
            let bufferCopy = buffer
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                logger.debug("Appending buffer to transcriber")
                self.transcriber.append(buffer: bufferCopy)
            }
        }

        // Start transcription
        try await transcriber.start(meetingID: meeting.id) { [weak self] chunkData in
            guard let self = self else { return }

            // Convert DTO to model on MainActor
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let chunk = chunkData.toModel()
                await self.handleTranscriptChunk(chunk)
            }
        }

        // Update state
        isRecording = true
        elapsedTime = 0

        // Start timer
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.elapsedTime += 1
            }
        }

        logger.info("Meeting capture started: \(meeting.id)")
    }

    /// Stop recording
    public func stopCapture() async {
        guard isRecording else { return }

        logger.info("Stopping meeting capture")

        // Stop timer
        timer?.invalidate()
        timer = nil

        // Stop transcription (emits final chunk asynchronously)
        transcriber.stop()

        // Stop audio recording
        do {
            try audioRecorder.stopRecording()
        } catch {
            logger.error("Failed to stop recording: \(error.localizedDescription)")
        }

        // Flush assembler
        await assembler.flush()

        // Wait for final chunk to be saved (it's emitted in an async Task)
        // This ensures the chunk is persisted before we schedule background work
        try? await Task.sleep(for: .milliseconds(500))

        // End meeting and ensure context is saved
        if let meeting = meeting {
            meeting.audioURL = audioURL
            do {
                try meetingRepo.endMeeting(meeting)

                // Explicitly save main context to persist all changes
                try context.save()
                logger.info("Saved all changes to main context before scheduling background task")

                // Schedule background summarization
                if #available(iOS 26, *) {
                    BackgroundTaskManager.shared.scheduleSummarization(for: meeting.id)
                }
            } catch {
                logger.error("Failed to end meeting: \(error.localizedDescription)")
            }
        }

        isRecording = false
        logger.info("Meeting capture stopped")
    }

    /// Mark a decision during recording
    public func markDecision(_ text: String, owner: String? = nil) {
        guard let meeting = meeting else { return }

        do {
            _ = try decisionRepo.add(meetingID: meeting.id, text: text, owner: owner)
            logger.info("Marked decision")
        } catch {
            logger.error("Failed to mark decision: \(error.localizedDescription)")
            errorMessage = "Failed to save decision"
        }
    }

    // MARK: - Private

    private func handleTranscriptChunk(_ chunk: TranscriptChunk) async {
        // Handle partial results (for live display only, don't save)
        if !chunk.isFinal {
            // Just update the live transcript with the partial result
            liveTranscript = chunk.text
            return
        }

        // Handle final results (save to database)
        // Convert to DTO for actor
        let chunkData = chunk.toData()

        // Add to assembler
        await assembler.append(chunkData)

        // Update live transcript (last 2 lines from assembler)
        let fullText = await assembler.getFullTranscript()
        let sentences = fullText.components(separatedBy: ". ")
        liveTranscript = sentences.suffix(2).joined(separator: ". ")

        // Add chunk to meeting's relationship array (establishes SwiftData relationship)
        if let meeting = meeting {
            meeting.transcriptChunks.append(chunk)
        }

        // Persist chunk (already on MainActor)
        do {
            try transcriptRepo.add(chunk)
            logger.info("Saved transcript chunk #\(chunk.index) to database")
        } catch {
            logger.error("Failed to persist chunk: \(error.localizedDescription)")
        }
    }

    /// Formatted elapsed time
    public var formattedTime: String {
        let hours = Int(elapsedTime) / 3600
        let minutes = (Int(elapsedTime) % 3600) / 60
        let seconds = Int(elapsedTime) % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}
