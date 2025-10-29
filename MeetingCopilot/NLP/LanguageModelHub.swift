//
//  LanguageModelHub.swift
//  MeetingCopilot
//
//  Central actor for managing Apple Intelligence Language Model session
//  Provides safe concurrency, cancellation, and timeout handling
//

#if canImport(FoundationModels)
import FoundationModels
#endif
import Foundation
import os

@available(iOS 26, *)
actor LanguageModelHub {
    static let shared = LanguageModelHub()
    private let log = Logger(subsystem: "MeetingCopilot", category: "nlp")
    #if canImport(FoundationModels)
    private let model: SystemLanguageModel
    private let session: LanguageModelSession
    private var isSessionBusy = false

    init() {
        // Use permissive guardrails for content transformations (meeting transcripts)
        model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
        session = LanguageModelSession(model: model)
        log.info("Initialized LanguageModelSession with permissive guardrails")
    }
    #else
    init() {}
    #endif

    func generate<T: Generable & Sendable>(
        prompt: String,
        as type: T.Type,
        temperature: Double = 0.2,
        timeout: TimeInterval = 15
    ) async throws -> T {
        #if canImport(FoundationModels)
        // Wait until session is available
        while isSessionBusy {
            log.debug("Session busy, waiting...")
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }

        isSessionBusy = true
        defer { isSessionBusy = false }

        do {
            return try await withTimeout(seconds: timeout) { [session] in
                let opts = GenerationOptions(temperature: temperature)
                let response = try await session.respond(to: prompt, generating: T.self, options: opts)
                return response.content
            }
        } catch is TimeoutError {
            log.error("LLM timeout after \(timeout, privacy: .public)s")
            throw LLMError.canceled
        } catch {
            log.error("LLM inference failed: \(String(describing: error), privacy: .public)")
            throw LLMError.inferenceFailed(underlying: error)
        }
        #else
        throw LLMError.notAvailable
        #endif
    }

    /// Generate a feedback attachment for reporting guardrail violations to Apple
    /// Use when you believe a guardrail was triggered incorrectly (false positive)
    func feedbackAttachment(
        sentiment: LanguageModelFeedback.Sentiment = .negative,
        issues: [LanguageModelFeedback.Issue],
        desiredOutput: Transcript.Entry
    ) async -> Data? {
        #if canImport(FoundationModels)
        do {
            let attachment = try await session.logFeedbackAttachment(
                sentiment: sentiment,
                issues: issues,
                desiredOutput: desiredOutput
            )
            log.info("Generated feedback attachment (\(attachment.count) bytes)")
            return attachment
        } catch {
            log.error("Failed to generate feedback attachment: \(error.localizedDescription)")
            return nil
        }
        #else
        return nil
        #endif
    }
}

struct TimeoutError: Error {}

@Sendable private func withTimeout<T: Sendable>(
    seconds: TimeInterval,
    _ body: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await body() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TimeoutError()
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
