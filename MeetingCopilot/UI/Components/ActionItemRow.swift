//
//  ActionItemRow.swift
//  MeetingCopilot
//
//  Row view for action items with checkbox
//

import SwiftUI

/// Row displaying an action item with optional selection
struct ActionItemRow: View {

    let actionItem: String
    @Binding var isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Checkbox
            Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                .font(.title3)
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .onTapGesture {
                    isSelected.toggle()
                }

            // Action text
            Text(parseActionItem(actionItem).text)
                .font(.body)
                .foregroundStyle(.primary)

            Spacer()

            // Due date badge if present
            if let dueText = parseActionItem(actionItem).dueDate {
                Text(dueText)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.orange.opacity(0.2))
                    )
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            isSelected.toggle()
        }
    }

    // MARK: - Parsing

    private func parseActionItem(_ item: String) -> (text: String, dueDate: String?) {
        // Extract due date pattern like "by Friday", "due Dec 15"
        let patterns = [
            #"\s+by\s+(\w+(?:\s+\d{1,2})?)"#,
            #"\s+due\s+(\w+(?:\s+\d{1,2})?)"#
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: item, range: NSRange(item.startIndex..., in: item)) {

                // Extract date text
                if let dateRange = Range(match.range(at: 1), in: item) {
                    let dateText = String(item[dateRange])

                    // Remove date from main text
                    if let matchRange = Range(match.range, in: item) {
                        let mainText = String(item[..<matchRange.lowerBound])
                        return (mainText.trimmingCharacters(in: .whitespaces), dateText)
                    }
                }
            }
        }

        return (item, nil)
    }
}

#Preview {
    VStack {
        ActionItemRow(
            actionItem: "Review the proposal by Friday",
            isSelected: .constant(false)
        )

        ActionItemRow(
            actionItem: "Update documentation due Dec 15",
            isSelected: .constant(true)
        )

        ActionItemRow(
            actionItem: "Schedule follow-up meeting",
            isSelected: .constant(false)
        )
    }
    .padding()
}
