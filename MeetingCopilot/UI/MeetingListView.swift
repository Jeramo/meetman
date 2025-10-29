//
//  MeetingListView.swift
//  MeetingCopilot
//
//  List of all meetings with search and navigation
//

import SwiftUI
import SwiftData

/// List view of all meetings
struct MeetingListView: View {

    @Query(sort: \Meeting.startedAt, order: .reverse)
    private var meetings: [Meeting]

    @State private var searchText = ""
    @State private var selectedMeeting: Meeting?

    var body: some View {
        NavigationStack {
            Group {
                if filteredMeetings.isEmpty {
                    emptyState
                } else {
                    meetingList
                }
            }
            .navigationTitle("Meetings")
            .navigationDestination(item: $selectedMeeting) { meeting in
                ReviewView(meeting: meeting)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink(destination: CaptureView()) {
                        Label("New Meeting", systemImage: "plus")
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search meetings")
        }
    }

    // MARK: - Components

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.slash")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("No Meetings Yet")
                .font(.title2.bold())

            Text("Start recording your first meeting")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            NavigationLink(destination: CaptureView()) {
                Label("Start Recording", systemImage: "mic.circle.fill")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var meetingList: some View {
        List(filteredMeetings) { meeting in
            Button {
                selectedMeeting = meeting
            } label: {
                MeetingRow(meeting: meeting)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    deleteMeeting(meeting)
                } label: {
                    Label("Delete", systemImage: "trash")
                }

                Button {
                    exportMeeting(meeting)
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .tint(.blue)
            }
        }
    }

    // MARK: - Filtered Meetings

    private var filteredMeetings: [Meeting] {
        if searchText.isEmpty {
            return meetings
        } else {
            return meetings.filter { meeting in
                meeting.title.localizedCaseInsensitiveContains(searchText) ||
                meeting.attendees.contains { $0.name.localizedCaseInsensitiveContains(searchText) }
            }
        }
    }

    // MARK: - Actions

    private func deleteMeeting(_ meeting: Meeting) {
        let context = Store.shared.mainContext
        context.delete(meeting)
        try? context.save()
    }

    private func exportMeeting(_ meeting: Meeting) {
        // TODO: Show share sheet
    }
}

// MARK: - Meeting Row

struct MeetingRow: View {

    let meeting: Meeting

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(meeting.title)
                    .font(.headline)

                Spacer()

                if meeting.isActive {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.red)
                            .frame(width: 8, height: 8)
                        Text("Live")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } else if meeting.summaryJSON != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            HStack {
                Label(meeting.startedAt.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")

                if let duration = meeting.duration {
                    Label(formatDuration(duration), systemImage: "clock")
                }

                if !meeting.attendees.isEmpty {
                    Label("\(meeting.attendees.count)", systemImage: "person.2")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if !meeting.transcriptChunks.isEmpty {
                Text(meeting.fullTranscript.prefix(100).trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
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

#Preview {
    MeetingListView()
        .modelContainer(Store.shared.container)
}
