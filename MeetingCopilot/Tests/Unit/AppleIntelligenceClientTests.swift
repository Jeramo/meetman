//
//  AppleIntelligenceClientTests.swift
//  MeetingCopilot
//
//  Unit tests for Apple Intelligence client (iOS 26+)
//

import Testing
@testable import MeetingCopilot

@Suite struct AppleIntelligenceClientTests {

    @Test func summary_roundtrip() async throws {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            let client = AppleIntelligenceClient()
            let transcript = """
            Alice: We agreed to ship v1 on Friday. Bob will integrate payments by Thursday.
            Charlie: I'll update docs.
            """

            let result = try await client.summarize(transcript: transcript, maxBullets: 5)

            #expect(!result.bullets.isEmpty)
            #expect(result.decisions.contains(where: { $0.localizedCaseInsensitiveContains("agreed") }))
            #expect(result.actionItems.contains(where: { $0.localizedCaseInsensitiveContains("Bob") }))
        }
        #endif
    }
}
