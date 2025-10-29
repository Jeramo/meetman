//
//  MeetingCopilotApp.swift
//  MeetingCopilot
//
//  Main app entry point for iOS 26
//

import SwiftUI
import SwiftData
import AppIntents

@main
@available(iOS 26, *)
struct MeetingCopilotApp: App {

    init() {
        // Register background tasks
        BackgroundTaskManager.shared.registerTasks()

        // Configure logging
        print("📱 Meeting Copilot starting")
        print("🤖 AI Backend: \(FeatureGates.aiEnabled ? "Apple Intelligence" : "Heuristic")")
        print("☁️ iCloud Sync: \(FeatureGates.iCloudEnabled ? "Enabled" : "Disabled")")
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .modelContainer(Store.shared.container)
        }
    }
}

// MARK: - App Shortcuts

@available(iOS 26, *)
struct MeetingCopilotShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartMeetingIntent(),
            phrases: [
                "Start a meeting in \(.applicationName)",
                "Record a meeting in \(.applicationName)"
            ],
            shortTitle: "Start Meeting",
            systemImageName: "mic.circle.fill"
        )

        AppShortcut(
            intent: StopMeetingIntent(),
            phrases: [
                "Stop meeting in \(.applicationName)",
                "End recording in \(.applicationName)"
            ],
            shortTitle: "Stop Meeting",
            systemImageName: "stop.circle.fill"
        )

        AppShortcut(
            intent: GenerateSummaryIntent(),
            phrases: [
                "Summarize meeting in \(.applicationName)",
                "Generate summary in \(.applicationName)"
            ],
            shortTitle: "Generate Summary",
            systemImageName: "doc.text.magnifyingglass"
        )
    }
}
