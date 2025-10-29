//
//  AudioPlaybackView.swift
//  MeetingCopilot
//
//  Audio playback with synchronized transcript highlighting
//

import SwiftUI
import AVFoundation
import Observation

/// Audio player with synchronized transcript highlighting
struct AudioPlaybackView: View {

    let meeting: Meeting
    @State private var viewModel: AudioPlaybackVM
    @Environment(\.dismiss) private var dismiss

    init(meeting: Meeting) {
        self.meeting = meeting
        _viewModel = State(initialValue: AudioPlaybackVM(meeting: meeting))
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                // Header
                headerSection

                Divider()

                // Transcript with highlighting
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(viewModel.chunks) { chunk in
                            ChunkView(
                                chunk: chunk,
                                isActive: viewModel.activeChunkID == chunk.id,
                                currentTime: viewModel.currentTime
                            )
                            .id(chunk.id)
                            .onTapGesture {
                                viewModel.seek(to: chunk.startTime)
                            }
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.activeChunkID) { _, newID in
                    if let newID = newID {
                        withAnimation {
                            proxy.scrollTo(newID, anchor: .center)
                        }
                    }
                }

                Divider()

                // Playback controls
                playbackControls
            }
        }
        .navigationTitle("Audio Playback")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.setup()
        }
        .onDisappear {
            viewModel.cleanup()
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 8) {
            Text(meeting.title)
                .font(.headline)

            HStack(spacing: 16) {
                Label(viewModel.formatTime(viewModel.currentTime), systemImage: "clock")
                Text("/")
                    .foregroundStyle(.secondary)
                Label(viewModel.formatTime(viewModel.duration), systemImage: "clock.fill")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding()
    }

    // MARK: - Playback Controls

    private var playbackControls: some View {
        VStack(spacing: 16) {
            // Progress slider
            HStack {
                Text(viewModel.formatTime(viewModel.currentTime))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Slider(
                    value: $viewModel.currentTime,
                    in: 0...max(viewModel.duration, 0.1),
                    onEditingChanged: { editing in
                        if !editing {
                            viewModel.seek(to: viewModel.currentTime)
                        }
                    }
                )

                Text(viewModel.formatTime(viewModel.duration))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            // Playback buttons
            HStack(spacing: 32) {
                // Rewind 10s
                Button {
                    viewModel.skip(by: -10)
                } label: {
                    Image(systemName: "gobackward.10")
                        .font(.title2)
                }

                // Play/Pause
                Button {
                    viewModel.togglePlayPause()
                } label: {
                    Image(systemName: viewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 60))
                }

                // Forward 10s
                Button {
                    viewModel.skip(by: 10)
                } label: {
                    Image(systemName: "goforward.10")
                        .font(.title2)
                }
            }

            // Playback speed
            speedControlsView
        }
        .padding()
        .background(Color(.systemBackground))
    }

    private var speedControlsView: some View {
        HStack {
            Text("Speed:")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { speed in
                speedButton(speed: Float(speed))
            }
        }
    }

    private func speedButton(speed: Float) -> some View {
        let isSelected = viewModel.playbackSpeed == speed
        return Button {
            viewModel.setPlaybackSpeed(speed)
        } label: {
            Text("\(speed, specifier: "%.2g")×")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.2))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .clipShape(Capsule())
        }
    }
}

// MARK: - Chunk View

struct ChunkView: View {
    let chunk: TranscriptChunk
    let isActive: Bool
    let currentTime: TimeInterval

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Timestamp
            Text(formatTimestamp(chunk.startTime))
                .font(.caption2)
                .foregroundStyle(.secondary)

            // Text with word-by-word highlighting
            Text(chunk.text)
                .font(.body)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isActive ? Color.accentColor.opacity(0.2) : Color(.secondarySystemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isActive ? Color.accentColor : Color.clear, lineWidth: 2)
                )
        }
    }

    private func formatTimestamp(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Audio Playback View Model

@MainActor
@Observable
final class AudioPlaybackVM {

    private let meeting: Meeting
    let chunks: [TranscriptChunk]

    var isPlaying = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var playbackSpeed: Float = 1.0
    var activeChunkID: UUID?

    private var audioPlayer: AVAudioPlayer?
    private var timer: Timer?

    init(meeting: Meeting) {
        self.meeting = meeting
        self.chunks = meeting.transcriptChunks.sorted { $0.startTime < $1.startTime }
    }

    func setup() {
        guard let audioURL = meeting.audioURL,
              FileManager.default.fileExists(atPath: audioURL.path) else {
            return
        }

        do {
            // Configure audio session for playback
            try AudioSessionManager.shared.configureForPlayback()

            audioPlayer = try AVAudioPlayer(contentsOf: audioURL)
            audioPlayer?.prepareToPlay()
            audioPlayer?.enableRate = true
            audioPlayer?.rate = playbackSpeed
            duration = audioPlayer?.duration ?? 0
        } catch {
            print("Failed to load audio: \(error)")
        }
    }

    func cleanup() {
        audioPlayer?.stop()
        timer?.invalidate()
        timer = nil
    }

    func togglePlayPause() {
        guard let player = audioPlayer else { return }

        if isPlaying {
            player.pause()
            timer?.invalidate()
            timer = nil
        } else {
            player.play()
            startTimer()
        }
        isPlaying.toggle()
    }

    func seek(to time: TimeInterval) {
        guard let player = audioPlayer else { return }
        let clampedTime = max(0, min(time, duration))
        player.currentTime = clampedTime
        currentTime = clampedTime
        updateActiveChunk()
    }

    func skip(by seconds: TimeInterval) {
        guard let player = audioPlayer else { return }
        let newTime = player.currentTime + seconds
        seek(to: newTime)
    }

    func setPlaybackSpeed(_ speed: Float) {
        playbackSpeed = speed
        audioPlayer?.rate = speed
    }

    func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.updateProgress()
            }
        }
    }

    private func updateProgress() {
        guard let player = audioPlayer else { return }
        currentTime = player.currentTime
        updateActiveChunk()

        // Stop when finished
        if !player.isPlaying && isPlaying {
            isPlaying = false
            timer?.invalidate()
            timer = nil
        }
    }

    private func updateActiveChunk() {
        // Find the chunk that contains the current time
        activeChunkID = chunks.first { chunk in
            currentTime >= chunk.startTime && currentTime < chunk.endTime
        }?.id
    }
}

#Preview {
    NavigationStack {
        AudioPlaybackView(meeting: Meeting(title: "Test Meeting"))
    }
}
