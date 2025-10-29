//
//  CaptureView.swift
//  MeetingCopilot
//
//  Live meeting capture interface
//

import SwiftUI

// MARK: - Language Support Banner (inlined)

struct LanguageSupportBanner: View {
    let detected: String
    let fallback: String
    let onUseFallback: (String) -> Void
    let onKeepDetected: () -> Void
    let onDontShowAgain: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Apple Intelligence doesn't fully support \"\(detected.uppercased())\".")
                .font(.headline)
            Text("Summaries may fail or be limited. Choose a fallback language for generation.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                Button("Use \(fallback.uppercased()) for summaries") {
                    onUseFallback(fallback)
                }
                .buttonStyle(.borderedProminent)

                Button("Keep \"\(detected.uppercased())\"") {
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

/// Main recording interface with live transcript
struct CaptureView: View {

    @State private var viewModel = MeetingVM()
    @State private var showingDecisionSheet = false
    @State private var showingLanguagePicker = false
    @State private var showingInputModeDialog = false
    @State private var decisionText = ""
    @State private var meetingTitle = ""
    @State private var completedMeeting: Meeting?
    @State private var isTypingMode = false
    @State private var manualTranscript = ""

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
        .navigationDestination(item: $completedMeeting) { meeting in
            ReviewView(meeting: meeting, autoGenerateSummary: true)
        }
        .sheet(isPresented: $showingDecisionSheet) {
            decisionSheet
        }
        .sheet(isPresented: $showingLanguagePicker) {
            languagePickerSheet
        }
        .confirmationDialog("Input Mode", isPresented: $showingInputModeDialog, titleVisibility: .visible) {
            Button("Speak (Microphone)") {
                isTypingMode = false
                startRecording()
            }
            Button("Type (Debug Mode)") {
                isTypingMode = true
                startRecording()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Choose how you want to provide input for this meeting")
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
        .onAppear {
            // Reset navigation state when returning to capture view
            completedMeeting = nil
            // Reset state for next recording
            if !viewModel.isRecording {
                meetingTitle = ""
                isTypingMode = false
                manualTranscript = ""
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

            // Language selector
            Button {
                showingLanguagePicker = true
            } label: {
                HStack {
                    Image(systemName: "globe")
                    Text(viewModel.userOverrideLocale?.displayName ?? "Auto (English)")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal)

            Text("Audio stays on this device. Tap to begin.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()

            // Start button
            Button {
                // Show input mode dialog
                showingInputModeDialog = true
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

            // Language support banner (if needed during recording)
            if #available(iOS 26, *), viewModel.showLanguageBanner, let info = viewModel.bannerInfo {
                LanguageSupportBanner(
                    detected: info.detected,
                    fallback: info.fallback,
                    onUseFallback: { chosen in
                        // Store chosen locale for summary generation
                        UserDefaults.standard.set(chosen, forKey: "preferred.output.locale")
                        viewModel.showLanguageBanner = false
                    },
                    onKeepDetected: {
                        // User wants to try with detected language
                        UserDefaults.standard.removeObject(forKey: "preferred.output.locale")
                        viewModel.showLanguageBanner = false
                    },
                    onDontShowAgain: {
                        viewModel.suppressWarningsForDetected()
                    }
                )
                .padding(.horizontal)
            }

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

            // Live transcript ticker or manual input
            VStack(alignment: .leading, spacing: 8) {
                Label(isTypingMode ? "Type Transcript (Debug)" : "Live Transcript", systemImage: isTypingMode ? "keyboard" : "waveform")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                if isTypingMode {
                    // Manual text input for debugging
                    TextEditor(text: $manualTranscript)
                        .font(.body)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.systemBackground))
                        )
                        .frame(height: 120)
                        .onChange(of: manualTranscript) { oldValue, newValue in
                            // Update live transcript as user types
                            viewModel.liveTranscript = newValue
                        }
                } else {
                    // Live transcript from microphone
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

                // Pause/Resume button
                Button {
                    if viewModel.isPaused {
                        Task {
                            do {
                                try await viewModel.resumeCapture()
                            } catch {
                                viewModel.errorMessage = error.localizedDescription
                            }
                        }
                    } else {
                        viewModel.pauseCapture()
                    }
                } label: {
                    Label(viewModel.isPaused ? "Resume" : "Pause", systemImage: viewModel.isPaused ? "play.fill" : "pause.fill")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding()
                        .frame(minWidth: 100)
                        .background(Color.orange)
                        .clipShape(Capsule())
                }

                // Stop button
                Button {
                    Task {
                        await viewModel.stopCapture()
                        // Navigate to review screen with the completed meeting
                        completedMeeting = viewModel.meeting
                    }
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding()
                        .frame(minWidth: 100)
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

    // MARK: - Language Picker Sheet

    private var languagePickerSheet: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        viewModel.userOverrideLocale = nil
                        showingLanguagePicker = false
                    } label: {
                        HStack {
                            Text("Auto (English)")
                            Spacer()
                            if viewModel.userOverrideLocale == nil {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                } header: {
                    Text("Default")
                } footer: {
                    Text("Automatically detects language and switches to English if needed.")
                }

                Section("All Languages") {
                    ForEach(ASRLocale.allCases, id: \.self) { locale in
                        Button {
                            viewModel.userOverrideLocale = locale
                            showingLanguagePicker = false
                        } label: {
                            HStack {
                                Text(locale.displayName)
                                Spacer()
                                if viewModel.userOverrideLocale == locale {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
            .navigationTitle("Transcription Language")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingLanguagePicker = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Helper Functions

    private func startRecording() {
        Task {
            do {
                if isTypingMode {
                    // Start in typing mode - create meeting but skip audio/ASR
                    try await viewModel.startCaptureTypingMode(title: meetingTitle.isEmpty ? nil : meetingTitle)
                } else {
                    // Normal microphone mode
                    try await viewModel.startCapture(title: meetingTitle.isEmpty ? nil : meetingTitle)
                }
            } catch {
                viewModel.errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    NavigationStack {
        CaptureView()
    }
}
