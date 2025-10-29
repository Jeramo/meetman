# Meeting Copilot - Project Structure

## 📁 Directory Layout

```
MeetingCopilot/
│
├── MeetingCopilotApp.swift          # App entry point, shortcuts provider
├── Info.plist                       # Permissions, background modes
├── README.md                        # Main documentation
├── QUICKSTART.md                    # Quick setup guide
├── .gitignore                       # Git ignore rules
│
├── Config/                          # Build-time configuration
│   ├── BuildFlags.swift             # BACKEND_AI, ICLOUD_SYNC flags
│   └── FeatureGates.swift           # Runtime availability checks
│
├── CoreModels/                      # Domain models and errors
│   ├── Entities.swift               # SwiftData @Model classes
│   ├── DomainErrors.swift           # Typed error enums
│   └── Migrations.swift             # Schema version management
│
├── Audio/                           # Audio capture subsystem
│   ├── AudioSession.swift           # AVAudioSession configuration
│   ├── AudioRecorder.swift          # AVAudioEngine wrapper
│   └── WavFileWriter.swift          # WAV file format writer
│
├── ASR/                             # Speech recognition
│   ├── LiveTranscriber.swift        # SFSpeechRecognizer streaming
│   └── TranscriptAssembler.swift    # Chunk ordering & deduplication
│
├── NLP/                             # Natural language processing
│   ├── LLMClient.swift              # Protocol + factory
│   ├── AppleIntelligenceClient.swift  # iOS 26+ stub (TODO: wire APIs)
│   ├── HeuristicSummarizer.swift    # Fallback implementation
│   └── PromptLibrary.swift          # Prompt templates
│
├── Actions/                         # EventKit integration
│   ├── TaskCreator.swift            # EKReminder creation
│   └── CalendarCreator.swift        # EKEvent creation
│
├── Persistence/                     # Data layer
│   ├── Store.swift                  # SwiftData container
│   ├── Repositories.swift           # CRUD operations
│   └── Exporters.swift              # Markdown/JSON export
│
├── Intents/                         # App Intents (Shortcuts/Siri)
│   ├── StartMeetingIntent.swift
│   ├── StopMeetingIntent.swift
│   ├── MarkDecisionIntent.swift
│   ├── CreateNextStepsIntent.swift
│   └── GenerateSummaryIntent.swift
│
├── Background/                      # Background processing
│   └── BackgroundTasks.swift        # BGTaskScheduler integration
│
├── UI/                              # SwiftUI interface
│   ├── RootView.swift               # Tab navigation
│   ├── MeetingListView.swift        # All meetings list
│   ├── CaptureView.swift            # Recording interface
│   ├── ReviewView.swift             # Summary & export
│   ├── Components/
│   │   ├── DecisionChip.swift       # Decision display
│   │   └── ActionItemRow.swift      # Action item with checkbox
│   └── ViewModels/
│       ├── MeetingVM.swift          # Capture orchestration
│       └── ReviewVM.swift           # Summary management
│
└── Tests/                           # Test suite (65+ tests)
    ├── Unit/
    │   ├── HeuristicSummarizerTests.swift    # 16 tests
    │   ├── TranscriptAssemblerTests.swift    # 12 tests
    │   ├── ExporterTests.swift               # 14 tests
    │   └── RepositoryTests.swift             # 23 tests
    └── UI/
        └── MeetingFlowUITests.swift          # Navigation & flow tests
```

## 🔗 Key Dependencies Between Modules

```
MeetingCopilotApp
  └─> RootView (UI)
       ├─> MeetingListView
       │    └─> ReviewView
       │         └─> ReviewVM
       │              ├─> NLPService (NLP)
       │              ├─> TaskCreator (Actions)
       │              └─> Exporters (Persistence)
       │
       ├─> CaptureView
       │    └─> MeetingVM
       │         ├─> AudioRecorder (Audio)
       │         ├─> LiveTranscriber (ASR)
       │         └─> Repositories (Persistence)
       │
       └─> SettingsView
            └─> FeatureGates (Config)

App Intents (isolated)
  └─> Direct calls to Repositories + NLP

Background Tasks
  └─> NLPService + Repositories
```

## 📝 File Size Breakdown

| Module | Files | Lines of Code (approx) |
|--------|-------|------------------------|
| Config | 2 | ~60 |
| CoreModels | 3 | ~250 |
| Audio | 3 | ~400 |
| ASR | 2 | ~250 |
| NLP | 4 | ~650 |
| Actions | 2 | ~350 |
| Persistence | 3 | ~500 |
| Intents | 5 | ~350 |
| Background | 1 | ~120 |
| UI | 8 | ~1200 |
| Tests | 5 | ~1500 |
| **TOTAL** | **38** | **~5630** |

## 🎯 Entry Points

### For Reading the Code

1. **Start**: `MeetingCopilotApp.swift` - Minimal bootstrap
2. **UI Flow**: `UI/RootView.swift` → tabs
3. **Recording**: `UI/CaptureView.swift` + `UI/ViewModels/MeetingVM.swift`
4. **Summarization**: `NLP/HeuristicSummarizer.swift` (working fallback)
5. **Data Model**: `CoreModels/Entities.swift`

### For Adding Features

- **New AI backend**: Implement `LLMClient` protocol (see `NLP/LLMClient.swift`)
- **New export format**: Add to `Persistence/Exporters.swift`
- **New UI view**: Add to `UI/` and wire to `RootView.swift`
- **New intent**: Add to `Intents/` and register in `MeetingCopilotApp.swift`

## 🧪 Testing Strategy

### Unit Tests (65 total)

- **NLP**: `HeuristicSummarizerTests` - Deterministic summarization
- **ASR**: `TranscriptAssemblerTests` - Chunk ordering & dedup
- **Export**: `ExporterTests` - Markdown/JSON generation
- **Data**: `RepositoryTests` - SwiftData CRUD operations

### UI Tests

- **Navigation**: Tab switching, view hierarchy
- **Accessibility**: VoiceOver labels, hit targets
- **Permissions**: Permission prompts (mocked)

## 🔧 Build Configuration

### Conditional Compilation

```swift
#if BACKEND_AI
    // Apple Intelligence code path
#else
    // Heuristic fallback
#endif

#if canImport(FoundationModels)
    import FoundationModels
#endif

@available(iOS 26, *)
// iOS 26+ only code
```

### Feature Flags

Runtime checks:
- `FeatureGates.aiEnabled` - Apple Intelligence available?
- `FeatureGates.iCloudEnabled` - iCloud sync on?

## 📊 Data Flow

### Recording Session

```
User taps "Start"
  → MeetingVM.startCapture()
    → AudioRecorder.startRecording()
      → Buffers → LiveTranscriber.append()
        → SFSpeechRecognizer → TranscriptChunk
          → TranscriptAssembler.append()
            → TranscriptRepository.add()
              → SwiftData persists

User taps "Stop"
  → MeetingVM.stopCapture()
    → AudioRecorder.stopRecording()
    → MeetingRepository.endMeeting()
    → BackgroundTaskManager.scheduleSummarization()
```

### Summary Generation

```
ReviewView.generateSummary()
  → ReviewVM.generateSummary()
    → NLPService.summarizeAll()
      → LLMClientFactory.makeDefault()
        → HeuristicSummarizer OR AppleIntelligenceClient
          → SummaryResult
            → MeetingRepository.update() (save summaryJSON)
              → ReviewView displays bullets/decisions/actions
```

## 🚀 Next Steps for Development

1. **Wire Apple Intelligence**: Edit `NLP/AppleIntelligenceClient.swift` when iOS 26 SDK is available
2. **Add Speaker Diarization**: Extend `TranscriptChunk` with speaker ID
3. **Improve UI**: Add animations, dark mode refinements
4. **Localization**: Add `.strings` files for i18n
5. **Performance**: Profile with Instruments, optimize large meetings

---

**Quick navigation**: Use Xcode's "Open Quickly" (Cmd+Shift+O) to jump to any file by name.
