# Meeting Copilot - Quick Start Guide

## ⚡ 5-Minute Setup

### 1. Prerequisites

- Xcode 16+ with iOS 26 SDK
- macOS 15+ (Sequoia or later)
- iOS 26 device or simulator

### 2. Build the App

```bash
# Clone and navigate
cd MeetingCopilot

# Open in Xcode
open MeetingCopilot.xcodeproj  # Or create project file

# Build and run
# Press Cmd+R in Xcode
```

### 3. First Recording

1. **Grant Permissions**: Tap "Allow" for Microphone and Speech Recognition
2. **Start Recording**: Tap the Record tab → "Start Recording"
3. **Speak**: Say a few sentences
4. **Watch Live Transcript**: See your words appear at the bottom
5. **Stop**: Tap "Stop" button

### 4. Generate Summary

1. Navigate to **Meetings** tab
2. Tap your first meeting
3. Tap **"Generate Summary"**
4. Review bullets, decisions, and action items
5. Export as Markdown or JSON

## 🎯 Key Features to Try

### Mark a Decision During Recording

While recording:
1. Tap **"Mark Decision"** pill
2. Type or dictate the decision
3. Tap **"Save Decision"**

### Create Reminders from Actions

After generating summary:
1. Check the action items you want
2. Tap **"Create Reminders"**
3. Grant Reminders permission if prompted
4. Check your Reminders app!

### Use Shortcuts

1. Open **Shortcuts** app
2. Create new shortcut
3. Add action: **"Start Meeting in Meeting Copilot"**
4. Run it with Siri: *"Hey Siri, run my standup shortcut"*

## 🛠️ Customization

### Enable Apple Intelligence (When Available)

Edit `Config/BuildFlags.swift`:

```swift
public let BACKEND_AI: Bool = true  // Use Apple Intelligence if available
```

### Enable iCloud Sync

```swift
public let ICLOUD_SYNC: Bool = true
```

Then rebuild (`Cmd+B`).

## 🧪 Run Tests

```bash
# Unit tests
Cmd+U in Xcode

# Or from command line
xcodebuild test -scheme MeetingCopilot -destination 'platform=iOS Simulator,name=iPhone 15 Pro'
```

## 🐛 Troubleshooting

### "Cannot record audio"
- Check Settings > Privacy & Security > Microphone
- Ensure Meeting Copilot has permission

### "Transcription not working"
- Check Settings > Privacy & Security > Speech Recognition
- Ensure on-device recognition is enabled

### "No summary generated"
- Ensure meeting has transcript chunks
- Check Console.app for errors (filter: "MeetingCopilot")

### "Build errors"
- Clean build folder: Shift+Cmd+K
- Update to latest Xcode
- Verify iOS 26 SDK is installed

## 📚 Next Steps

- Read [README.md](README.md) for architecture details
- Review [Apple Intelligence Integration](README.md#-apple-intelligence-integration)
- Explore the codebase starting from `MeetingCopilotApp.swift`
- Check out the test suite for usage examples

## 🎓 Code Tour

**Start here**:
1. `MeetingCopilotApp.swift` - App entry point
2. `UI/RootView.swift` - Main navigation
3. `UI/CaptureView.swift` - Recording interface
4. `NLP/HeuristicSummarizer.swift` - Summarization logic

**Key abstractions**:
- `LLMClient` protocol - AI backend abstraction
- `MeetingRepository` - SwiftData persistence
- `AudioRecorder` - AVAudioEngine wrapper
- `LiveTranscriber` - Speech recognition

Enjoy building with **Meeting Copilot**! 🚀
