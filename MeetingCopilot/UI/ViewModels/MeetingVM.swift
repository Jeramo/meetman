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
import NaturalLanguage
#if canImport(FoundationModels)
import FoundationModels
#endif

private let logger = Logger(subsystem: "com.jeramo.meetingman", category: "ui")

// MARK: - Language Support Helpers (inlined temporarily)

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

        let hypotheses = recognizer.languageHypotheses(withMaximum: 1)
        let confidence = hypotheses[dominantLanguage] ?? 0.0

        let bcp47 = mapToFullBCP47(dominantLanguage.rawValue)

        return LanguageDetectionResult(
            bcp47: bcp47,
            name: nil,
            confidence: confidence,
            method: .naturalLanguage
        )
    }

    /// Map ISO 639-1 code to BCP-47 with region
    private func mapToFullBCP47(_ iso639: String) -> String {
        switch iso639.lowercased() {
        case "sv": return "sv-se"
        case "en": return "en-us"
        case "fr": return "fr-fr"
        case "de": return "de-de"
        case "es": return "es-es"
        case "it": return "it-it"
        case "pt": return "pt-br"
        case "ja": return "ja-jp"
        case "ko": return "ko-kr"
        case "zh": return "zh-hans"
        case "nb", "no": return "nb-no"
        case "da": return "da-dk"
        case "nl": return "nl-nl"
        case "fi": return "fi-fi"
        default: return iso639
        }
    }
}

/// Runtime gate for Apple Intelligence language coverage
@available(iOS 26, *)
enum LLMLanguageSupport {
    /// iOS 26.0 supported languages
    private static let ios26_0Languages: Set<String> = [
        "en-us", "en-gb", "en-au",
        "fr-fr", "fr-ca",
        "de-de",
        "it-it",
        "pt-br",
        "es-es", "es-us", "es-419",
        "zh-hans",
        "ja-jp",
        "ko-kr"
    ]

    /// iOS 26.1+ additional languages
    @available(iOS 26.1, *)
    private static let ios26_1AdditionalLanguages: Set<String> = [
        "zh-hant",      // Chinese (Traditional)
        "da-dk",        // Danish
        "nl-nl",        // Dutch
        "nb-no", "nn-no", // Norwegian (Bokmål, Nynorsk)
        "pt-pt",        // Portuguese (Portugal)
        "sv-se",        // Swedish
        "tr-tr",        // Turkish
        "vi-vn"         // Vietnamese
    ]

    /// Get supported languages based on iOS version
    private static var supportedBCP47: Set<String> {
        var languages = ios26_0Languages
        if #available(iOS 26.1, *) {
            languages.formUnion(ios26_1AdditionalLanguages)
        }
        return languages
    }

    static func normalize(_ bcp47: String) -> String {
        bcp47.replacingOccurrences(of: "_", with: "-").lowercased()
    }

    static func isSupported(_ bcp47: String) -> Bool {
        let tag = normalize(bcp47)
        let supported = supportedBCP47
        if supported.contains(tag) { return true }
        let base = tag.split(separator: "-").first.map(String.init) ?? tag
        if supported.contains(base) { return true }
        return supported.contains(where: { $0.hasPrefix(base + "-") })
    }

    static func suggestedFallback(for bcp47: String) -> String {
        let tag = normalize(bcp47)
        let base = tag.split(separator: "-").first.map(String.init) ?? tag

        // Check if native language is supported on current iOS version
        if #available(iOS 26.1, *) {
            // iOS 26.1+ supports more languages directly
            switch base {
            case "sv": return "sv-se"  // Swedish now supported
            case "da": return "da-dk"  // Danish now supported
            case "nl": return "nl-nl"  // Dutch now supported
            case "no", "nb", "nn": return "nb-no"  // Norwegian now supported
            case "tr": return "tr-tr"  // Turkish now supported
            case "vi": return "vi-vn"  // Vietnamese now supported
            case "pt":
                // Check region - Portugal now supported
                if tag.contains("pt-pt") { return "pt-pt" }
                return "pt-br"
            case "zh":
                // Check if Traditional Chinese
                if tag.contains("hant") || tag.contains("tw") || tag.contains("hk") {
                    return "zh-hant"
                }
                return "zh-hans"
            default:
                break
            }
        }

        // iOS 26.0 fallbacks (or iOS 26.1+ for unsupported languages)
        switch base {
        case "pt": return "pt-br"
        case "es": return "es-es"
        case "fr": return "fr-fr"
        case "de": return "de-de"
        case "it": return "it-it"
        case "nl", "da", "no", "sv", "tr", "vi": return "en-gb"  // Fallback to English on 26.0
        case "zh": return "zh-hans"
        default: return "en-us"
        }
    }
}

@available(iOS 26, *)
struct AppleIntelligenceGate {
    enum Status {
        case available(outputLocale: String)
        case unsupported(detected: String, fallback: String)
        case notAvailableOnDevice
    }

    static func status(for detectedBCP47: String) -> Status {
        #if canImport(FoundationModels)
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

    // Language support state
    public var detectedLanguageBCP47: String?
    public var showLanguageBanner: Bool = false
    public var bannerInfo: (detected: String, fallback: String)?
    private var hasDetectedLanguage: Bool = false

    // ASR language override (nil = use policy default)
    public var userOverrideLocale: ASRLocale?

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

        // Choose ASR locale using policy
        let asrLocale = LanguagePolicy.initialASRLocale(userOverride: self.userOverrideLocale)
        logger.info("Selected ASR locale: \(asrLocale.rawValue) (override: \(self.userOverrideLocale?.rawValue ?? "none"))")

        // Start transcription first
        try transcriber.start(
            locale: asrLocale,
            meetingID: meeting.id
        ) { [weak self] chunkData in
            guard let self = self else { return }

            // Convert DTO to model on MainActor
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let chunk = chunkData.toModel()
                await self.handleTranscriptChunk(chunk)
            }
        }

        // Start audio recording - buffers will be fed to transcriber
        try await audioRecorder.startRecording(to: audioURL!) { [weak self] buffer in
            guard let self = self else { return }
            // Forward audio buffers to transcriber
            self.transcriber.append(buffer: buffer)
        }

        // Update state
        isRecording = true
        elapsedTime = 0
        hasDetectedLanguage = false

        // Language detection will happen after first transcript chunk arrives

        // Start timer
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.elapsedTime += 1
            }
        }

        logger.info("Meeting capture started: \(meeting.id)")
    }

    /// Start capture in typing mode (for debugging - no microphone/ASR)
    public func startCaptureTypingMode(title: String?, attendees: [PersonRef] = []) async throws {
        guard !isRecording else { return }

        logger.info("Starting meeting capture in typing mode (debug)")

        // Create meeting record
        let meetingTitle = title ?? "Meeting \(Date().formatted(date: .abbreviated, time: .shortened))"
        meeting = try meetingRepo.create(title: meetingTitle, attendees: attendees)

        guard let meeting = meeting else {
            throw PersistenceError.saveFailed(underlying: NSError(domain: "MeetingVM", code: -1))
        }

        // No audio file in typing mode
        audioURL = nil

        // Update state
        isRecording = true
        elapsedTime = 0
        hasDetectedLanguage = false
        liveTranscript = ""

        // Start timer
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.elapsedTime += 1
            }
        }

        logger.info("Meeting capture started in typing mode: \(meeting.id)")
    }

    /// Stop recording
    public func stopCapture() async {
        guard isRecording else {
            logger.warning("stopCapture called but not recording")
            return
        }

        logger.info("Stopping meeting capture")

        // Stop timer first
        timer?.invalidate()
        timer = nil

        // Check if typing mode (no audio URL)
        let isTypingMode = (audioURL == nil)

        if !isTypingMode {
            // Normal mode: stop audio and transcription
            do {
                try audioRecorder.stopRecording()
                logger.info("Audio recorder stopped")
            } catch {
                logger.error("Failed to stop recording: \(error.localizedDescription)")
            }

            transcriber.stop()
            logger.info("Transcriber stopped")

            // Flush assembler
            await assembler.flush()
        } else {
            // Typing mode: save the typed transcript as a single chunk
            logger.info("Stopping typing mode - saving typed transcript")
            if let meeting = meeting, !liveTranscript.isEmpty {
                let chunk = TranscriptChunk(
                    meetingID: meeting.id,
                    index: 0,
                    text: liveTranscript,
                    startTime: 0,
                    endTime: elapsedTime,
                    isFinal: true
                )
                do {
                    try transcriptRepo.add(chunk)
                    meeting.transcriptChunks.append(chunk)
                    logger.info("Saved typed transcript as single chunk")
                } catch {
                    logger.error("Failed to save typed transcript: \(error.localizedDescription)")
                }
            }
        }

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

        // Clear state for next recording
        isRecording = false
        liveTranscript = ""
        audioURL = nil
        hasDetectedLanguage = false

        logger.info("Meeting capture stopped, state cleared")
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

        // Detect language once we have enough text (iOS 26+)
        if #available(iOS 26, *), !hasDetectedLanguage, fullText.count >= 100 {
            hasDetectedLanguage = true
            logger.info("Detecting language from \(fullText.count) chars of transcript")

            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let result = await LanguageDetector.shared.detect(fullText)
                logger.info("Language detection complete: \(result.bcp47) (\(result.name ?? "unknown"), \(result.confidence), \(result.method.rawValue))")
                self.onLanguageDetected(result.bcp47)
            }
        }

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

    // MARK: - Language Support

    @available(iOS 26, *)
    private var suppressed: Set<String> {
        get {
            let raw = UserDefaults.standard.string(forKey: "llm.suppressWarning.langs") ?? ""
            return Set(raw.split(separator: ",").map { String($0) })
        }
        set {
            UserDefaults.standard.set(newValue.sorted().joined(separator: ","), forKey: "llm.suppressWarning.langs")
        }
    }

    @available(iOS 26, *)
    public func onLanguageDetected(_ bcp47: String) {
        detectedLanguageBCP47 = bcp47
        let norm = LLMLanguageSupport.normalize(bcp47)
        if suppressed.contains(norm) { return }

        switch AppleIntelligenceGate.status(for: bcp47) {
        case .available:
            showLanguageBanner = false
            bannerInfo = nil
        case .unsupported(let detected, let fallback):
            bannerInfo = (detected, fallback)
            showLanguageBanner = true
        case .notAvailableOnDevice:
            // You may show a different banner if the framework is missing/disabled
            bannerInfo = nil
            showLanguageBanner = false
        }
    }

    @available(iOS 26, *)
    public func suppressWarningsForDetected() {
        guard let d = detectedLanguageBCP47 else { return }
        let normalized = LLMLanguageSupport.normalize(d)
        var s = suppressed
        s.insert(normalized)
        suppressed = s
        showLanguageBanner = false
    }
}
