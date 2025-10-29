//
//  DecisionChip.swift
//  MeetingCopilot
//
//  Compact chip view for displaying decisions
//

import SwiftUI

/// Compact chip for displaying a decision
struct DecisionChip: View {

    let decision: Decision

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(decision.text)
                .font(.subheadline)
                .foregroundStyle(.primary)

            if let owner = decision.owner {
                Label(owner, systemImage: "person.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.accentColor.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 1)
        )
    }
}

#Preview {
    DecisionChip(
        decision: Decision(
            meetingID: UUID(),
            text: "Decided to proceed with Option B",
            owner: "Alice"
        )
    )
    .padding()
}
