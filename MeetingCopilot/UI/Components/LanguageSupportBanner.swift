//
//  LanguageSupportBanner.swift
//  MeetingCopilot
//
//  Warning banner for unsupported Apple Intelligence languages
//

import SwiftUI

struct LanguageSupportBanner: View {
    let detected: String
    let fallback: String
    let onUseFallback: (String) -> Void
    let onKeepDetected: () -> Void
    let onDontShowAgain: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Apple Intelligence doesn't fully support "\(detected.uppercased())".")
                .font(.headline)
            Text("Summaries may fail or be limited. Choose a fallback language for generation.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                Button("Use \(fallback.uppercased()) for summaries") {
                    onUseFallback(fallback)
                }
                .buttonStyle(.borderedProminent)

                Button("Keep "\(detected.uppercased())"") {
                    onKeepDetected()
                }
                .buttonStyle(.bordered)
            }

            Button("Don't show again for \(detected.uppercased())") {
                onDontShowAgain()
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.yellow.opacity(0.35)))
        .accessibilityElement(children: .combine)
    }
}
