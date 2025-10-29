//
//  CaptureView.swift
//  MeetingCopilot
//
//  Live meeting capture interface
//

import SwiftUI

/// Main recording interface with live transcript
struct CaptureView: View {

    @State private var viewModel = MeetingVM()
    @State private var showingDecisionSheet = false
    @State private var decisionText = ""
    @State private var meetingTitle = ""

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [.accentColor.opacity(0.1), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 32) {

                if !viewModel.isRecording {
                    // Pre-recording setup
                    setupView
                } else {
                    // Active recording view
                    recordingView
                }
            }
            .padding()
        }
        .navigationTitle("Meeting Capture")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingDecisionSheet) {
            decisionSheet
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            if let error = viewModel.errorMessage {
                Text(error)
            }
        }
    }

    // MARK: - Setup View

    private var setupView: some View {
        VStack(spacing: 24) {
            Spacer()

            // Microphone icon
            Image(systemName: "mic.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.tint)
                .symbolEffect(.pulse)

            Text("Ready to Record")
                .font(.title2.bold())

            // Title input
            TextField("Meeting Title (optional)", text: $meetingTitle)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)

            Text("Audio stays on this device. Tap to begin.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()

            // Start button
            Button {
                Task {
                    do {
                        try await viewModel.startCapture(title: meetingTitle.isEmpty ? nil : meetingTitle)
                    } catch {
                        viewModel.errorMessage = error.localizedDescription
                    }
                }
            } label: {
                Label("Start Recording", systemImage: "record.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Recording View

    private var recordingView: some View {
        VStack(spacing: 24) {

            // Timer
            VStack(spacing: 8) {
                Text(viewModel.formattedTime)
                    .font(.system(size: 48, weight: .bold, design: .monospaced))
                    .foregroundStyle(.tint)

                HStack(spacing: 4) {
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)
                    Text("Recording")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 32)

            Spacer()

            // Live transcript ticker
            VStack(alignment: .leading, spacing: 8) {
                Label("Live Transcript", systemImage: "waveform")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                ScrollView {
                    Text(viewModel.liveTranscript.isEmpty ? "Listening..." : viewModel.liveTranscript)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.systemBackground))
                        )
                }
                .frame(height: 120)
            }

            Spacer()

            // Actions
            HStack(spacing: 16) {
                // Mark decision
                Button {
                    showingDecisionSheet = true
                } label: {
                    Label("Mark Decision", systemImage: "flag.fill")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .padding()
                        .background(Color.orange)
                        .clipShape(Capsule())
                }

                Spacer()

                // Stop button
                Button {
                    Task {
                        await viewModel.stopCapture()
                        dismiss()
                    }
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding()
                        .frame(minWidth: 120)
                        .background(Color.red)
                        .clipShape(Capsule())
                }
            }
            .padding(.bottom)
        }
    }

    // MARK: - Decision Sheet

    private var decisionSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("What was decided?")
                    .font(.headline)
                    .padding(.top)

                TextField("Enter decision...", text: $decisionText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .padding()

                Button("Save Decision") {
                    viewModel.markDecision(decisionText)
                    decisionText = ""
                    showingDecisionSheet = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(decisionText.isEmpty)

                Spacer()
            }
            .navigationTitle("Mark Decision")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        decisionText = ""
                        showingDecisionSheet = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    NavigationStack {
        CaptureView()
    }
}
