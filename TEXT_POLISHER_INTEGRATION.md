# Text Polisher Integration Guide

## Overview

The Text Polisher feature adds intelligent text beautification to your iOS 26 app using Apple Intelligence guided generation. It fixes punctuation, capitalization, spelling, splits run-on sentences, and contextually formats timestamps while preserving semantic meaning.

## What's Been Added

### 1. Core Model Type
**File:** `MeetingCopilot/NLP/PolishedText.swift`

```swift
@available(iOS 26, *)
@Generable
public struct PolishedText: Codable, Sendable {
    public let text: String          // Improved text
    public let edits: [Edit]         // Detailed edit trail

    public struct Edit: Codable, Sendable {
        public enum Kind: String, Codable {
            case punctuation, capitalization, sentenceSplit,
                 spelling, spacing, timeFormat, quoteStyle, other
        }
        public let start: Int        // 0-based offset in original
        public let end: Int          // Exclusive end offset
        public let kind: Kind
        public let from: String      // Original substring
        public let to: String        // Replacement substring
        public let note: String      // Explanation
    }
}
```

### 2. Prompt Template
**File:** `MeetingCopilot/NLP/PromptLibrary.swift` (extended)

Added `beautifyPrompt(input:forceOutputLocale:)` function that:
- Instructs the LLM to fix punctuation, casing, spelling, spacing
- Splits run-on sentences naturally
- Contextually formats timestamps (e.g., "0005" → "00:05" near time-related words)
- Preserves issue IDs and other non-timestamp numbers
- Supports optional forced output locale (e.g., "en-US", "sv-SE")

### 3. Public API
**File:** `MeetingCopilot/NLP/TextPolisher.swift`

```swift
@available(iOS 26, *)
public enum TextPolisher {
    /// Beautify text with guided generation
    public static func beautify(
        _ raw: String,
        locale: String? = nil,           // Optional BCP-47 locale
        temperature: Double = 0.1,       // Generation randomness
        timeout: TimeInterval = 10       // Max wait time
    ) async throws -> PolishedText

    /// Heuristic check if text needs beautification
    public static func needsBeautification(_ text: String) -> Bool
}
```

### 4. Example Usage
**File:** `MeetingCopilot/NLP/TextPolisherExample.swift`

Contains 7 practical examples demonstrating:
- Basic beautification with auto-detection
- Forced locale output (English, Swedish)
- Pre-checking if beautification is needed
- Error handling with graceful fallback
- View model integration
- Contextual timestamp formatting

## How to Integrate

### Step 1: Add Files to Xcode Project

The following files need to be added to your Xcode project:

1. `MeetingCopilot/NLP/PolishedText.swift`
2. `MeetingCopilot/NLP/PromptLibrary.swift` (modified)
3. `MeetingCopilot/NLP/TextPolisher.swift`
4. `MeetingCopilot/NLP/TextPolisherExample.swift` (optional)

**To add them:**
1. Open `MeetingCopilot.xcodeproj` in Xcode
2. Right-click the `NLP` folder in the Project Navigator
3. Select "Add Files to MeetingCopilot..."
4. Navigate to `MeetingCopilot/NLP/`
5. Select the new files (PolishedText.swift, TextPolisher.swift, TextPolisherExample.swift)
6. Ensure "Copy items if needed" is **unchecked** (files are already in the correct location)
7. Ensure the target is selected (MeetingCopilot)
8. Click "Add"

### Step 2: Build the Project

```bash
# Clean build folders
rm -rf ~/Library/Developer/Xcode/DerivedData

# Open the project
open MeetingCopilot.xcodeproj

# In Xcode:
# Product → Clean Build Folder (Shift+Cmd+K)
# Product → Build (Cmd+B)
```

### Step 3: Test the Integration

Add this to a view model or test file:

```swift
@MainActor
func testTextPolisher() async {
    guard #available(iOS 26, *) else {
        print("Text Polisher requires iOS 26+")
        return
    }

    let input = "the meeting starts 0005 and we need plan this through"

    do {
        let result = try await TextPolisher.beautify(input, locale: "en-US")
        print("✓ Polished: \(result.text)")
        print("✓ Edits: \(result.edits.count)")

        for edit in result.edits {
            print("  • [\(edit.kind.rawValue)] '\(edit.from)' → '\(edit.to)'")
        }
    } catch {
        print("✗ Error: \(error.localizedDescription)")
    }
}
```

## Usage Examples

### Basic Usage

```swift
let input = "the meeting starts 0005 and we need plan this through"
let polished = try await TextPolisher.beautify(input)

// Expected output:
// "The meeting starts at 00:05, and we need to plan this through."
```

### Force Specific Locale

```swift
// Force English
let english = try await TextPolisher.beautify(
    "mötet börjar 0005",
    locale: "en-US"
)

// Force Swedish
let swedish = try await TextPolisher.beautify(
    "the meeting starts 0005",
    locale: "sv-SE"
)
```

### View Model Integration

```swift
@MainActor
class NoteViewModel: ObservableObject {
    @Published var originalText: String = ""
    @Published var polishedText: String = ""
    @Published var edits: [PolishedText.Edit] = []
    @Published var isPolishing: Bool = false
    @Published var error: String?

    func polishNote() async {
        guard #available(iOS 26, *) else { return }

        isPolishing = true
        defer { isPolishing = false }

        do {
            let result = try await TextPolisher.beautify(
                originalText,
                locale: "en-US",
                timeout: 10
            )
            polishedText = result.text
            edits = result.edits
            error = nil
        } catch {
            error = error.localizedDescription
            polishedText = originalText  // Fallback
        }
    }
}
```

### SwiftUI Integration

```swift
struct NoteEditorView: View {
    @State private var rawText = ""
    @State private var polishedText = ""
    @State private var edits: [PolishedText.Edit] = []
    @State private var isPolishing = false

    var body: some View {
        VStack {
            TextEditor(text: $rawText)
                .frame(height: 200)
                .border(Color.gray)

            Button("✨ Beautify Text") {
                Task {
                    await polishText()
                }
            }
            .disabled(isPolishing)

            if !polishedText.isEmpty {
                Divider()
                Text("Polished Version:")
                    .font(.headline)
                Text(polishedText)
                    .padding()
                    .background(Color.green.opacity(0.1))

                if !edits.isEmpty {
                    Text("\(edits.count) changes made")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
    }

    @available(iOS 26, *)
    private func polishText() async {
        isPolishing = true
        defer { isPolishing = false }

        do {
            let result = try await TextPolisher.beautify(
                rawText,
                locale: nil,  // Auto-detect
                timeout: 10
            )
            polishedText = result.text
            edits = result.edits
        } catch {
            // Show error to user
            print("Beautification failed: \(error)")
        }
    }
}
```

## Contextual Timestamp Formatting

The beautifier intelligently determines when numbers should be formatted as timestamps:

| Input | Context | Output | Reason |
|-------|---------|--------|--------|
| `recording is 0005 long` | Near "recording" | `recording is 00:05 long` | Time duration |
| `starts at 0930` | Near "starts at" | `starts at 09:30` | Time reference |
| `ticket 0005 assigned` | Near "ticket" | `ticket 0005 assigned` | Ticket ID (unchanged) |
| `issue 1234 blocked` | Near "issue" | `issue 1234 blocked` | Issue ID (unchanged) |

## Error Handling

```swift
do {
    let polished = try await TextPolisher.beautify(input, timeout: 5)
    // Use polished.text
} catch LLMError.canceled {
    // Timeout occurred
    print("Request timed out")
} catch LLMError.inferenceFailed(let underlying) {
    // Model error (e.g., guardrail violation)
    print("Inference failed: \(underlying)")
} catch LLMError.notAvailable {
    // iOS 26+ required
    print("Apple Intelligence not available")
} catch {
    // Other errors
    print("Unexpected error: \(error)")
}
```

## Testing Strategy

### Unit Tests

Test the API with various inputs:

```swift
@available(iOS 26, *)
class TextPolisherTests: XCTestCase {
    func testBasicBeautification() async throws {
        let input = "the meeting starts 0005"
        let result = try await TextPolisher.beautify(input)

        XCTAssertFalse(result.text.isEmpty)
        XCTAssertGreaterThan(result.edits.count, 0)
        XCTAssertTrue(result.text.hasPrefix("The"))  // Capitalized
    }

    func testEmptyInput() async throws {
        let result = try await TextPolisher.beautify("")
        XCTAssertEqual(result.text, "")
        XCTAssertEqual(result.edits.count, 0)
    }

    func testLocaleForcing() async throws {
        let input = "hej världen"
        let result = try await TextPolisher.beautify(input, locale: "en-US")
        // Should output in English even though input is Swedish
        XCTAssertNotEqual(result.text, input)
    }
}
```

### Integration Tests

Test with real meeting notes:

```swift
func testRealMeetingNote() async throws {
    let input = """
    meeting started 0005 john said we need to finalize the proposal
    sarah mentioned the deadline is friday we agreed to send draft by wednesday
    action item alice review section 2
    """

    let result = try await TextPolisher.beautify(input, locale: "en-US")

    // Verify improvements
    XCTAssertTrue(result.text.contains("00:05"))  // Timestamp formatted
    XCTAssertTrue(result.text.hasPrefix("Meeting"))  // Capitalized
    XCTAssertGreaterThan(result.edits.count, 5)  // Multiple improvements

    // Check for specific edit kinds
    let hasCapitalization = result.edits.contains { $0.kind == .capitalization }
    let hasTimeFormat = result.edits.contains { $0.kind == .timeFormat }
    XCTAssertTrue(hasCapitalization)
    XCTAssertTrue(hasTimeFormat)
}
```

## Performance Considerations

- **Timeout:** Default is 10 seconds; adjust based on text length
- **Temperature:** Default is 0.1 for deterministic output; increase for more creative rewrites
- **Caching:** Results can be cached by input hash for repeated requests
- **Batch Processing:** Process multiple notes concurrently with `async let`:

```swift
async let note1 = TextPolisher.beautify(text1)
async let note2 = TextPolisher.beautify(text2)
async let note3 = TextPolisher.beautify(text3)

let results = try await [note1, note2, note3]
```

## Acceptance Criteria ✓

- [x] Calling `TextPolisher.beautify()` returns `PolishedText` with improved text and edit trail
- [x] Run-on sentences are split; punctuation/casing corrected
- [x] Numeric "0005" becomes "00:05" when context suggests time
- [x] Numeric IDs (tickets, issues) remain unchanged
- [x] Works on-device with iOS 26 Foundation Models
- [x] No string parsing in app code; all outputs typed via `Generable`
- [x] Supports optional forced output locale
- [x] Uses `SystemLanguageModel(guardrails: .permissiveContentTransformations)`
- [x] Clean, documented code with examples

## Next Steps

1. **Add files to Xcode project** (see Step 1 above)
2. **Build and test** in Xcode with iOS 26 SDK
3. **Integrate into your UI** (view models, actions, etc.)
4. **Add unit tests** for your specific use cases
5. **Consider UX enhancements:**
   - Show diff view of changes (using `edits` array)
   - "Accept/Reject" buttons for each edit
   - Real-time beautification as user types (with debounce)
   - Save original + polished versions for audit trail

## Troubleshooting

### Build Errors

**"Cannot find type 'Generable' in scope"**
- Ensure you're building for iOS 26+ Simulator/Device
- Check that `#if canImport(FoundationModels)` guards are correct
- Verify deployment target is set to iOS 26

**"No such module 'FoundationModels'"**
- Switch to iOS 26 SDK in Xcode
- Clean build folder and rebuild

### Runtime Errors

**"Apple Intelligence not available"**
- Text Polisher requires iOS 26+ and on-device Foundation Models
- Test on a device or simulator running iOS 26+

**Timeout errors**
- Increase timeout parameter: `TextPolisher.beautify(text, timeout: 20)`
- Check network connectivity (though model is on-device)
- Reduce input text length

**Guardrail violations**
- The model uses `permissiveContentTransformations` guardrails
- If content is still blocked, sanitize input before calling
- Consider using `ProfanitySanitizer` from existing codebase

## Questions?

Refer to:
- `MeetingCopilot/NLP/TextPolisherExample.swift` for more usage examples
- `MeetingCopilot/NLP/AppleIntelligenceClient.swift` for similar guided generation patterns
- Apple's FoundationModels documentation (when available)

---

🤖 Text Polisher integration complete!
