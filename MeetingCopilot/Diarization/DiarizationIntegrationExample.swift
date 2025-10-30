//
//  DiarizationIntegrationExample.swift
//  MeetingCopilot
//
//  Example integration patterns for speaker diarization
//

import Foundation
import SwiftData
import OSLog

// MARK: - Example 1: Post-Recording Diarization

/// Add this method to your MeetingViewModel or ReviewViewModel
extension ReviewVM {

    /// Perform speaker diarization on the meeting after recording ends
    func performDiarization() async {
        guard let meeting = meeting else { return }

        // Initialize diarization service
        let modelURL = Bundle.main.url(
            forResource: "SpeakerEmbedder",
            withExtension: "mlmodelc"
        )

        let service = DiarizationService(
            embedderURL: modelURL,
            context: modelContext
        )

        do {
            // Run diarization with progress updates
            _ = try await service.diarize(meeting: meeting) { progress, status in
                Task { @MainActor in
                    // Update UI with progress
                    self.diarizationProgress = progress
                    self.diarizationStatus = status
                }
            }

            // Generate and display statistics
            if let stats = service.generateStatistics(for: meeting) {
                Task { @MainActor in
                    self.speakerStats = stats.formatted()
                }
            }

            print("Diarization completed successfully")

        } catch {
            print("Diarization failed: \(error.localizedDescription)")
            // Show error to user
        }
    }
}

// MARK: - Example 2: Background Task Integration

/// Add speaker diarization as a background task
extension BackgroundTasks {

    /// Register diarization background task
    static func registerDiarizationTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.jeramo.meetingman.diarize",
            using: nil
        ) { task in
            handleDiarizationTask(task as! BGProcessingTask)
        }
    }

    /// Handle background diarization
    private static func handleDiarizationTask(_ task: BGProcessingTask) {
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        Task {
            do {
                // Get all meetings without speaker labels
                let container = try ModelContainer(for: Meeting.self)
                let context = ModelContext(container)

                let meetings = try fetchMeetingsNeedingDiarization(context: context)

                guard let meeting = meetings.first else {
                    task.setTaskCompleted(success: true)
                    return
                }

                // Perform diarization
                let service = DiarizationService(
                    embedderURL: Bundle.main.url(
                        forResource: "SpeakerEmbedder",
                        withExtension: "mlmodelc"
                    ),
                    context: context
                )

                _ = try await service.diarize(meeting: meeting)

                task.setTaskCompleted(success: true)

                // Schedule next run if more meetings need processing
                if meetings.count > 1 {
                    scheduleDiarizationTask()
                }

            } catch {
                print("Background diarization failed: \(error)")
                task.setTaskCompleted(success: false)
            }
        }
    }

    /// Fetch meetings that need diarization
    private static func fetchMeetingsNeedingDiarization(
        context: ModelContext
    ) throws -> [Meeting] {
        // Find meetings with transcript chunks but no speaker labels
        let allMeetings = try context.fetch(Meeting.self)

        return allMeetings.filter { meeting in
            !meeting.transcriptChunks.isEmpty &&
            meeting.transcriptChunks.allSatisfy { $0.speakerID == nil }
        }
    }

    /// Schedule background diarization task
    static func scheduleDiarizationTask() {
        let request = BGProcessingTaskRequest(
            identifier: "com.jeramo.meetingman.diarize"
        )
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false // Can run on battery
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60) // Wait 1 minute

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Failed to schedule diarization task: \(error)")
        }
    }
}

// MARK: - Example 3: UI Integration

/// Add diarization controls to ReviewView
struct DiarizationButton: View {
    let meeting: Meeting
    @State private var isDiarizing = false
    @State private var progress: Double = 0
    @State private var status: String = ""
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack {
            if isDiarizing {
                VStack(spacing: 8) {
                    ProgressView(value: progress)
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else {
                Button("Identify Speakers") {
                    Task {
                        await runDiarization()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func runDiarization() async {
        isDiarizing = true

        let modelURL = Bundle.main.url(
            forResource: "SpeakerEmbedder",
            withExtension: "mlmodelc"
        )

        let service = DiarizationService(
            embedderURL: modelURL,
            context: modelContext
        )

        do {
            _ = try await service.diarize(meeting: meeting) { p, s in
                Task { @MainActor in
                    progress = p
                    status = s
                }
            }

            // Refresh UI to show speaker labels
            isDiarizing = false

        } catch {
            print("Diarization error: \(error)")
            isDiarizing = false
        }
    }
}

// MARK: - Example 4: Speaker-Aware Summary Generation

/// Generate summary with speaker attribution
func generateSpeakerAwareSummary(
    for meeting: Meeting,
    llmClient: LLMClient
) async throws -> MeetingSummary {

    // Get labeled segments
    let chunks = meeting.transcriptChunks.sorted { $0.index < $1.index }

    let labeledSegments = chunks.compactMap { chunk -> LabeledSegment? in
        guard let speakerID = chunk.speakerID, !chunk.text.isEmpty else {
            return nil
        }
        return LabeledSegment(
            speakerID: speakerID,
            text: chunk.text,
            start: chunk.startTime,
            end: chunk.endTime
        )
    }

    // Use speaker-aware prompt if we have labeled segments
    let prompt: String
    if !labeledSegments.isEmpty {
        prompt = PromptLibrary.speakerAwareSummary(
            labeledSegments: labeledSegments,
            maxBullets: 6
        )
    } else {
        // Fallback to regular summary
        prompt = PromptLibrary.summaryPrompt(
            transcript: meeting.fullTranscript,
            maxBullets: 6
        )
    }

    // Generate summary
    return try await llmClient.generateSummary(prompt: prompt)
}

// MARK: - Example 5: Export with Speaker Labels

/// Export transcript with speaker tags
func exportTranscriptWithSpeakers(meeting: Meeting) -> String {
    let chunks = meeting.transcriptChunks.sorted { $0.index < $1.index }

    let labeledSegments = chunks.compactMap { chunk -> LabeledSegment? in
        guard let speakerID = chunk.speakerID else { return nil }
        return LabeledSegment(
            speakerID: speakerID,
            text: chunk.text,
            start: chunk.startTime,
            end: chunk.endTime
        )
    }

    // Format with timestamps
    return PromptLibrary.formatTranscriptWithSpeakers(
        labeledSegments,
        includeTimestamps: true
    )
}

// MARK: - Example 6: Speaker Statistics View

struct SpeakerStatsView: View {
    let meeting: Meeting
    @State private var statistics: SpeakerStatistics?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Speaker Statistics")
                .font(.headline)

            if let stats = statistics {
                ForEach(stats.speakers.keys.sorted(), id: \.self) { speakerID in
                    if let speakerStats = stats.speakers[speakerID] {
                        SpeakerStatRow(
                            speakerID: speakerID,
                            stats: speakerStats,
                            totalDuration: stats.totalDuration
                        )
                    }
                }
            } else {
                Text("No speaker statistics available")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .onAppear {
            loadStatistics()
        }
    }

    private func loadStatistics() {
        let chunks = meeting.transcriptChunks.sorted { $0.index < $1.index }

        let segments = chunks.compactMap { chunk -> LabeledSegment? in
            guard let speakerID = chunk.speakerID else { return nil }
            return LabeledSegment(
                speakerID: speakerID,
                text: chunk.text,
                start: chunk.startTime,
                end: chunk.endTime
            )
        }

        guard !segments.isEmpty else { return }

        let stats = Alignment.computeStatistics(segments)
        let totalDuration = meeting.duration ?? 0

        statistics = SpeakerStatistics(
            speakers: stats.mapValues {
                SpeakerStats(talkTime: $0.talkTime, wordCount: $0.wordCount)
            },
            totalDuration: totalDuration
        )
    }
}

struct SpeakerStatRow: View {
    let speakerID: String
    let stats: SpeakerStats
    let totalDuration: TimeInterval

    var body: some View {
        HStack {
            Circle()
                .fill(colorForSpeaker(speakerID))
                .frame(width: 12, height: 12)

            Text(speakerID)
                .font(.subheadline)
                .fontWeight(.medium)

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(formatDuration(stats.talkTime))
                    .font(.subheadline)

                Text("\(Int(percentage))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("\(stats.wordCount) words")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
        }
    }

    private var percentage: Double {
        totalDuration > 0 ? (stats.talkTime / totalDuration) * 100 : 0
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration / 60)
        let seconds = Int(duration.truncatingRemainder(dividingBy: 60))
        return "\(minutes)m \(seconds)s"
    }

    private func colorForSpeaker(_ speakerID: String) -> Color {
        // Assign consistent colors to speakers
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .cyan]
        let index = speakerID.last.flatMap { Int(String($0)) } ?? 0
        return colors[index % colors.count]
    }
}

// MARK: - Example 7: Feature Flag

extension FeatureGates {
    /// Check if speaker diarization is available
    static var isSpeakerDiarizationAvailable: Bool {
        // Require iOS 26+ and Core ML model present
        guard #available(iOS 26, *) else { return false }

        return Bundle.main.url(
            forResource: "SpeakerEmbedder",
            withExtension: "mlmodelc"
        ) != nil
    }

    /// Check if diarization should run automatically
    static var shouldAutoDiarize: Bool {
        // Could be user preference
        UserDefaults.standard.bool(forKey: "autoDiarization")
    }
}
