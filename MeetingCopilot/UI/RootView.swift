//
//  RootView.swift
//  MeetingCopilot
//
//  Root navigation structure
//

import SwiftUI

/// Root view with tab navigation
struct RootView: View {

    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {

            // Meetings list
            MeetingListView()
                .tabItem {
                    Label("Meetings", systemImage: "list.bullet")
                }
                .tag(0)

            // Quick capture
            NavigationStack {
                CaptureView()
            }
            .tabItem {
                Label("Record", systemImage: "mic.circle")
            }
            .tag(1)

            // Settings (placeholder)
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(2)
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("AI Backend")
                        Spacer()
                        Text(FeatureGates.aiEnabled ? "Apple Intelligence" : "Heuristic")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("iCloud Sync")
                        Spacer()
                        Text(FeatureGates.iCloudEnabled ? "Enabled" : "Disabled")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Configuration")
                }

                Section {
                    LabeledContent("Privacy Policy") {
                        Text("All data stays on device")
                            .foregroundStyle(.secondary)
                    }

                    LabeledContent("Permissions") {
                        VStack(alignment: .trailing) {
                            Text("Microphone")
                            Text("Speech Recognition")
                            Text("Reminders")
                            Text("Calendar")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Privacy")
                } footer: {
                    Text("Meeting Copilot processes all audio and transcripts locally. No data is sent to external servers.")
                }

                Section {
                    LabeledContent("Version") {
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }

                    LabeledContent("Build") {
                        Text("iOS 26+")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    RootView()
        .modelContainer(Store.shared.container)
}
