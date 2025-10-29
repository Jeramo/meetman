# Meeting Copilot

[![iOS](https://img.shields.io/badge/iOS-26.0+-blue.svg)](https://developer.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

**Meeting Copilot** is a production-grade, privacy-first iOS app for recording, transcribing, and summarizing meetings. All processing happens **on-device** with no network connectivity required.

## 🎯 Features

- ✅ **Offline-First**: Audio recording, transcription, and AI summarization work entirely on-device
- 🎙️ **Live Transcription**: Real-time speech-to-text using Apple's Speech framework
- 🤖 **Dual AI Backend**: Apple Intelligence (iOS 26+) with heuristic fallback
- 📝 **Smart Summaries**: Automatic extraction of bullets, decisions, and action items
- 🔔 **Reminders Integration**: Create EKReminders directly from action items
- 📅 **Calendar Integration**: Schedule follow-up meetings with deeplinks
- 📤 **Export Options**: Markdown and JSON export formats
- 🎯 **App Intents**: Full Shortcuts and Siri integration
- 🔒 **Privacy-First**: Explicit consent flow; no cloud uploads
- 🧪 **Well Tested**: 65+ unit tests, UI tests, accessibility support

## 🏗️ Architecture

### Modular Design

```
MeetingCopilot/
├── Config/              # Build flags and feature gates
├── CoreModels/          # SwiftData entities and domain errors
├── Audio/               # AVAudioEngine, WAV writer
├── ASR/                 # Speech recognition and transcript assembly
├── NLP/                 # LLM abstraction (Apple Intelligence + Heuristic)
├── Actions/             # EventKit integration (Reminders, Calendar)
├── Persistence/         # SwiftData repositories and exporters
├── Intents/             # App Intents for Shortcuts/Siri
├── Background/          # BGTaskScheduler for post-meeting processing
├── UI/                  # SwiftUI views, view models, components
└── Tests/               # Unit and UI tests
```

### Key Technologies

- **SwiftData**: Local persistence with optional iCloud sync
- **AVAudioEngine**: 16kHz mono PCM audio capture
- **Speech Framework**: On-device speech recognition
- **NaturalLanguage**: Heuristic NLP for summarization fallback
- **EventKit**: Reminders and Calendar integration
- **AppIntents**: Shortcuts and Siri support
- **BackgroundTasks**: Post-meeting summarization

## 🚀 Getting Started

### Requirements

- **Xcode 16+** (with iOS 26 SDK)
- **iOS 26.0+** deployment target
- **Swift 6.0+**
- Physical device or simulator with microphone support

### Build and Run

1. **Clone the repository**:
   ```bash
   git clone https://github.com/yourusername/MeetingCopilot.git
   cd MeetingCopilot
   ```

2. **Open in Xcode**:
   ```bash
   open MeetingCopilot.xcodeproj
   ```

3. **Configure build flags** (optional):
   Edit `Config/BuildFlags.swift`:
   ```swift
   public let BACKEND_AI: Bool = true    // Use Apple Intelligence
   public let ICLOUD_SYNC: Bool = false  // Enable iCloud sync
   ```

4. **Build and run**:
   - Select your target device/simulator
   - Press `Cmd+R` to build and run

### First Launch

On first launch, the app will request permissions for:
- 🎤 **Microphone**: Required for recording
- 🗣️ **Speech Recognition**: Required for transcription
- 🔔 **Reminders** (optional): For creating action items
- 📅 **Calendar** (optional): For scheduling follow-ups

All permissions can be granted/revoked in Settings > Privacy & Security.

## 🤖 Apple Intelligence Integration

### Current Status

The app includes **stub implementations** for Apple's Foundation Models framework. When iOS 26 ships with the actual APIs, follow these steps to wire them:

### Integration Steps

1. **Verify Framework Availability**:
   ```swift
   // In NLP/AppleIntelligenceClient.swift
   public static var isAvailable: Bool {
       #if canImport(FoundationModels)
       return FoundationModels.isAvailable() // Use actual API check
       #else
       return false
       #endif
   }
   ```

2. **Implement Summarization**:
   ```swift
   private func performSummarization(transcript: String, maxBullets: Int) async throws -> SummaryResult {
       // Load on-device model
       let model = try await FoundationModels.loadModel(.summarization)

       // Build prompt
       let prompt = PromptLibrary.summaryPrompt(transcript: transcript, maxBullets: maxBullets)

       // Configure inference
       let config = InferenceConfig(
           temperature: 0.2,  // Low for factual output
           maxTokens: 1024
       )

       // Generate
       let response = try await model.generate(prompt: prompt, config: config)

       // Parse JSON
       guard let data = response.text.data(using: .utf8),
             let result = try? JSONDecoder().decode(SummaryResult.self, from: data) else {
           throw LLMError.badJSON
       }

       return result
   }
   ```

3. **Implement Refinement**:
   ```swift
   private func performRefinement(context: SummaryResult, newChunk: String) async throws -> SummaryResult {
       let model = try await FoundationModels.loadModel(.summarization)

       let contextJSON = String(data: try JSONEncoder().encode(context), encoding: .utf8) ?? "{}"
       let prompt = PromptLibrary.refinementPrompt(contextJSON: contextJSON, newChunk: newChunk)

       let config = InferenceConfig(temperature: 0.2, maxTokens: 1024)
       let response = try await model.generate(prompt: prompt, config: config)

       guard let data = response.text.data(using: .utf8),
             let result = try? JSONDecoder().decode(SummaryResult.self, from: data) else {
           throw LLMError.badJSON
       }

       return result
   }
   ```

### Fallback Behavior

When Apple Intelligence is unavailable, the app uses **HeuristicSummarizer**:
- Pure Swift implementation using NaturalLanguage framework
- Deterministic, testable, and reliable
- Extracts decisions via pattern matching (e.g., "decided to", "agreed that")
- Extracts action items via regex and imperative sentence detection
- Scores sentences for importance using keyword matching and NER

## 📊 Data Model

### SwiftData Entities

**Meeting**
```swift
@Model
final class Meeting {
    var id: UUID
    var title: String
    var startedAt: Date
    var endedAt: Date?
    var attendees: [PersonRef]
    var audioURL: URL?
    var transcriptChunks: [TranscriptChunk]  // Cascade delete
    var decisions: [Decision]                // Cascade delete
    var summaryJSON: String?
}
```

**TranscriptChunk**
```swift
@Model
final class TranscriptChunk {
    var id: UUID
    var meetingID: UUID
    var index: Int
    var text: String
    var startTime: TimeInterval
    var endTime: TimeInterval
    var isFinal: Bool
}
```

**Decision**
```swift
@Model
final class Decision {
    var id: UUID
    var meetingID: UUID
    var text: String
    var owner: String?
    var timestamp: Date
}
```

### Value Types

**SummaryResult** (JSON-serializable)
```swift
struct SummaryResult: Codable {
    let bullets: [String]
    let decisions: [String]
    let actionItems: [String]  // Format: "Owner — Verb — Object [Due]"
}
```

## 🎬 Usage

### Recording a Meeting

1. Tap **Record** tab or use "Start Recording" button
2. (Optional) Enter meeting title and attendees
3. Tap **Start Recording** → Grant permissions if prompted
4. Speak normally; live transcript appears at bottom
5. Tap **Mark Decision** to flag important commitments
6. Tap **Stop** when finished

### Reviewing & Exporting

1. Navigate to **Meetings** tab
2. Select a meeting from the list
3. Tap **Generate Summary** (if not auto-generated)
4. Review bullets, decisions, and action items
5. Select action items → **Create Reminders**
6. Tap **Export** → Choose Markdown or JSON

### Shortcuts Integration

Create automations in the Shortcuts app:

- **"Start my standup"** → Triggers `StartMeetingIntent`
- **"Summarize last meeting"** → Triggers `GenerateSummaryIntent`
- **"Mark decision"** → Triggers `MarkDecisionIntent` with dictated text

## 🧪 Testing

### Run Unit Tests

```bash
# From Xcode
Cmd+U

# From command line
xcodebuild test \
  -scheme MeetingCopilot \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro'
```

**Coverage**:
- `HeuristicSummarizerTests`: 16 tests (NLP logic)
- `TranscriptAssemblerTests`: 12 tests (Chunk ordering, deduplication)
- `ExporterTests`: 14 tests (Markdown/JSON generation)
- `RepositoryTests`: 23 tests (SwiftData CRUD operations)
- **Total**: 65 tests

### Run UI Tests

```bash
xcodebuild test \
  -scheme MeetingCopilotUITests \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro'
```

## 🔐 Privacy Model

### Data Storage

- **Local-First**: All data stored in SwiftData container
- **No Cloud**: No network requests in MVP (optional iCloud sync via flag)
- **Audio**: WAV files saved to app's Documents directory
- **Transcripts**: Stored in SwiftData, indexed for search

### Permissions

- **Microphone**: Required for recording
- **Speech Recognition**: Required for transcription (`requiresOnDeviceRecognition: true`)
- **Reminders**: Optional, requested only when creating action items
- **Calendar**: Optional, requested only when scheduling events

### Data Lifecycle

1. **During Meeting**: Audio buffered to disk, streamed to ASR
2. **Post-Meeting**: Background task generates summary
3. **User Control**: Explicit delete in Meetings list
4. **Export**: User-initiated, saved to temp directory for sharing

## 🛠️ Configuration

### Build Flags

Edit `Config/BuildFlags.swift`:

```swift
#if DEBUG
public let BACKEND_AI: Bool = true    // Use Apple Intelligence (if available)
public let ICLOUD_SYNC: Bool = false  // Enable SwiftData iCloud sync
#else
public let BACKEND_AI: Bool = true
public let ICLOUD_SYNC: Bool = false
#endif
```

### Feature Gates

Runtime checks in `Config/FeatureGates.swift`:

```swift
FeatureGates.aiEnabled           // True if Apple Intelligence available
FeatureGates.iCloudEnabled       // True if iCloud sync enabled
FeatureGates.backgroundProcessingAvailable  // True on iOS 26+
```

## 📝 Logging

The app uses `os.Logger` with categorized subsystems:

```swift
import OSLog

let audioLogger = Logger(subsystem: "com.meetingcopilot.app", category: "audio")
let asrLogger = Logger(subsystem: "com.meetingcopilot.app", category: "asr")
let nlpLogger = Logger(subsystem: "com.meetingcopilot.app", category: "nlp")
```

View logs in **Console.app** by filtering for process `MeetingCopilot`.

## 🚧 Known Limitations

1. **Apple Intelligence Stubs**: Requires iOS 26 SDK with actual FoundationModels framework
2. **Background Limits**: iOS enforces strict time limits on BGProcessingTask (~30s typically)
3. **ASR Accuracy**: SFSpeechRecognizer quality varies by device/language
4. **iCloud Sync**: Not tested in multi-device scenarios (requires Apple Developer account)
5. **Large Meetings**: Very long meetings (>2 hours) may exceed optimal summarization context window

## 🛤️ Roadmap

- [ ] **Speaker Diarization**: Identify individual speakers in transcript
- [ ] **Multi-language**: Support languages beyond English
- [ ] **Live Collaboration**: Share live transcript via peer-to-peer
- [ ] **Templates**: Meeting templates (standup, 1-on-1, retrospective)
- [ ] **Rich Export**: PDF export with formatting
- [ ] **Siri Shortcuts Phrases**: Custom phrase registration
- [ ] **Watch App**: Start/stop recording from Apple Watch

## 📄 License

MIT License - see [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Built with **SwiftUI**, **SwiftData**, and Apple's native frameworks
- NLP heuristics inspired by TextRank and keyword extraction algorithms
- UI/UX follows Apple Human Interface Guidelines

## 📞 Support

For issues, feature requests, or questions:
- Open an issue on [GitHub](https://github.com/yourusername/MeetingCopilot/issues)
- Review the [FAQ](docs/FAQ.md)
- Check [API Documentation](docs/API.md)

---

**Meeting Copilot** · Offline-first meeting intelligence for iOS 26+
