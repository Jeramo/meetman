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
    private var isSessionBusy = false

    init() {
        // Use permissive guardrails for content transformations (meeting transcripts)
        model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
        log.info("Initialized LanguageModelHub with permissive guardrails")
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
        // Check model availability before attempting to use it
        switch model.availability {
        case .available:
            log.debug("Model available, proceeding with generation")
        case .unavailable(let reason):
            log.error("Model unavailable: \(String(describing: reason))")
            switch reason {
            case .modelNotReady:
                throw LLMError.modelNotReady
            case .appleIntelligenceNotEnabled:
                throw LLMError.appleIntelligenceNotEnabled
            case .deviceNotEligible:
                throw LLMError.deviceNotEligible
            @unknown default:
                throw LLMError.notAvailable
            }
        }

        // Wait until session is available
        while isSessionBusy {
            log.debug("Session busy, waiting...")
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }

        isSessionBusy = true
        defer { isSessionBusy = false }

        do {
            // Create a NEW session for each request to avoid context accumulation
            // LanguageModelSession maintains conversation history which can exceed context window
            log.debug("Creating new LanguageModelSession for request")
            let session = LanguageModelSession(model: model)

            return try await withTimeout(seconds: timeout) {
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
