//
//  ReviewView.swift
//  MeetingCopilot
//
//  Meeting review with summary, decisions, and actions
//

import SwiftUI

/// Review meeting summary and export
struct ReviewView: View {

    @State private var viewModel: ReviewVM
    @State private var selectedActionItems = Set<String>()
    @State private var showingShareSheet = false
    @State private var exportURL: URL?
    @State private var showingAudioPlayback = false

    private let autoGenerateSummary: Bool

    init(meeting: Meeting, autoGenerateSummary: Bool = false) {
        _viewModel = State(initialValue: ReviewVM(meeting: meeting))
        self.autoGenerateSummary = autoGenerateSummary
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {

                // Header
                if let meeting = viewModel.meeting {
                    meetingHeader(meeting)

                    // Audio playback button
                    if meeting.audioURL != nil {
                        audioPlaybackButton
                    }
                }

                // Transcript polish section (optional, before summary)
                if #available(iOS 26, *) {
                    transcriptPolishSection
                }

                // Summary section
                if viewModel.summary != nil {
                    summarySection
                    decisionsSection
                    actionItemsSection
                } else {
                    generateSummaryPrompt
                }

                // Export section
                exportSection

                Spacer(minLength: 32)
            }
            .padding()
        }
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showingAudioPlayback) {
            if let meeting = viewModel.meeting {
                AudioPlaybackView(meeting: meeting)
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            if let url = exportURL {
                ShareSheet(items: [url])
            }
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") {
                viewModel.clearMessages()
            }
        } message: {
            if let error = viewModel.errorMessage {
                Text(error)
            }
        }
        .alert("Success", isPresented: .constant(viewModel.successMessage != nil)) {
            Button("OK") {
                viewModel.clearMessages()
            }
        } message: {
            if let success = viewModel.successMessage {
                Text(success)
            }
        }
        .onAppear {
            // Auto-generate summary if requested and not already present
            if autoGenerateSummary && viewModel.summary == nil {
                Task {
                    await viewModel.generateSummary()
                }
            }
        }
    }

    // MARK: - Components

    private func meetingHeader(_ meeting: Meeting) -> some View {
        VStack(spacing: 8) {
            Text(meeting.title)
                .font(.title2.bold())

            HStack {
                Label(meeting.startedAt.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                if let duration = meeting.duration {
                    Label(formatDuration(duration), systemImage: "clock")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            if !meeting.attendees.isEmpty {
                Text("Attendees: \(meeting.attendees.map(\.name).joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var audioPlaybackButton: some View {
        Button {
            showingAudioPlayback = true
        } label: {
            HStack {
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                Text("Listen with Transcript")
                    .font(.headline)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.accentColor.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.accentColor, lineWidth: 1)
            )
        }
        .foregroundStyle(.primary)
    }

    private var generateSummaryPrompt: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("No summary yet")
                .font(.headline)

            Text("Generate an AI summary with key points, decisions, and action items.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                Task {
                    await viewModel.generateSummary()
                }
            } label: {
                if viewModel.isGeneratingSummary {
                    ProgressView()
                        .tint(.white)
                } else {
                    Label("Generate Summary", systemImage: "sparkles")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isGeneratingSummary)
        }
        .padding(.vertical, 32)
    }

    @available(iOS 26, *)
    @ViewBuilder
    private var transcriptPolishSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Text Polish", systemImage: "sparkles")
                    .font(.headline)

                Spacer()

                Button {
                    Task {
                        if #available(iOS 26, *) {
                            await viewModel.polishTranscript()
                        }
                    }
                } label: {
                    if viewModel.isPolishingText {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Label("Polish Transcript", systemImage: "wand.and.stars")
                            .font(.caption)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isPolishingText || viewModel.meeting?.transcriptChunks.isEmpty == true)
            }

            if let polishedText = viewModel.polishedTranscript {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Polished Transcript:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(polishedText)
                        .font(.body)
                        .padding(8)
                        .background(Color.green.opacity(0.05))
                        .cornerRadius(6)

                    if !viewModel.transcriptEdits.isEmpty {
                        Text("\(viewModel.transcriptEdits.count) improvements made")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }

    @ViewBuilder
    private var summarySection: some View {
        if let summary = viewModel.summary, !summary.bullets.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Summary", systemImage: "list.bullet")
                        .font(.headline)

                    Spacer()

                    if #available(iOS 26, *) {
                        Button {
                            Task {
                                await viewModel.polishSummaryItems()
                            }
                        } label: {
                            if viewModel.isPolishingText {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Label("Polish All", systemImage: "wand.and.stars")
                                    .font(.caption)
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(viewModel.isPolishingText)
                    }
                }

                ForEach(summary.bullets, id: \.self) { bullet in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .foregroundStyle(.tint)
                        Text(bullet)
                            .font(.body)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
            )
        }
    }

    @ViewBuilder
    private var decisionsSection: some View {
        if let summary = viewModel.summary, !summary.decisions.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Label("Decisions", systemImage: "flag.fill")
                    .font(.headline)

                ForEach(summary.decisions, id: \.self) { decision in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(decision)
                            .font(.body)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
            )
        }
    }

    @ViewBuilder
    private var actionItemsSection: some View {
        if let summary = viewModel.summary, !summary.actionItems.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Action Items", systemImage: "checklist")
                        .font(.headline)

                    Spacer()

                    Button {
                        Task {
                            _ = try? await viewModel.pushActionItemsToReminders()
                        }
                    } label: {
                        if viewModel.isCreatingReminders {
                            ProgressView()
                        } else {
                            Label("Create Reminders", systemImage: "bell.badge")
                                .font(.caption)
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(selectedActionItems.isEmpty || viewModel.isCreatingReminders)
                }

                ForEach(summary.actionItems, id: \.self) { item in
                    ActionItemRow(
                        actionItem: item,
                        isSelected: Binding(
                            get: { selectedActionItems.contains(item) },
                            set: { isSelected in
                                if isSelected {
                                    selectedActionItems.insert(item)
                                } else {
                                    selectedActionItems.remove(item)
                                }
                            }
                        )
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
            )
        }
    }

    private var exportSection: some View {
        VStack(spacing: 12) {
            Label("Export", systemImage: "square.and.arrow.up")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                Button {
                    exportAs(format: .markdown)
                } label: {
                    Label("Markdown", systemImage: "doc.text")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    exportAs(format: .json)
                } label: {
                    Label("JSON", systemImage: "doc.badge.gearshape")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }

    // MARK: - Actions

    private enum ExportFormat {
        case markdown
        case json
    }

    private func exportAs(format: ExportFormat) {
        do {
            let url: URL
            switch format {
            case .markdown:
                url = try viewModel.exportMarkdown()
            case .json:
                url = try viewModel.exportJSON()
            }

            exportURL = url
            showingShareSheet = true
        } catch {
            viewModel.errorMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    NavigationStack {
        ReviewView(
            meeting: Meeting(
                title: "Team Standup",
                attendees: [PersonRef(name: "Alice"), PersonRef(name: "Bob")]
            )
        )
    }
}
