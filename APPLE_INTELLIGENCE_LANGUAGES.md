# Apple Intelligence Language Support

## Version-Conditional Language Support

The app now dynamically supports different languages based on iOS version.

### iOS 26.0 Languages (13 total)
✅ **Available now:**
- English (US, GB, AU)
- French (France, Canada)
- German (Germany)
- Italian (Italy)
- Portuguese (Brazil)
- Spanish (Spain, US, Latin America)
- Chinese (Simplified)
- Japanese (Japan)
- Korean (Korea)

**BCP-47 tags:**
```
en-us, en-gb, en-au
fr-fr, fr-ca
de-de
it-it
pt-br
es-es, es-us, es-419
zh-hans
ja-jp
ko-kr
```

### iOS 26.1+ Additional Languages (8 more)
✅ **Added in iOS 26.1:**
- Chinese (Traditional) - `zh-hant`
- Danish - `da-dk`
- Dutch - `nl-nl`
- Norwegian (Bokmål, Nynorsk) - `nb-no`, `nn-no`
- Portuguese (Portugal) - `pt-pt`
- Swedish - `sv-se` ⭐
- Turkish - `tr-tr`
- Vietnamese - `vi-vn`

**Total iOS 26.1+:** 21 languages

## Implementation

### Dynamic Language Detection
```swift
// iOS 26.0
LLMLanguageSupport.isSupported("sv-se")  // false → shows banner

// iOS 26.1+
LLMLanguageSupport.isSupported("sv-se")  // true → no banner needed!
```

### Smart Fallback Logic

#### iOS 26.0 Behavior:
```swift
Swedish (sv-se) → English (en-gb) fallback
Danish (da-dk) → English (en-gb) fallback
Dutch (nl-nl) → English (en-gb) fallback
```

**User sees banner:**
```
"Apple Intelligence doesn't fully support Swedish."
[Use EN-GB for summaries] [Keep Swedish]
```

#### iOS 26.1+ Behavior:
```swift
Swedish (sv-se) → Natively supported ✓
Danish (da-dk) → Natively supported ✓
Dutch (nl-nl) → Natively supported ✓
```

**No banner shown!** User can generate summaries directly in their language.

## Code Architecture

### Version Checking
```swift
@available(iOS 26, *)
enum LLMLanguageSupport {
    private static let ios26_0Languages: Set<String> = [...]

    @available(iOS 26.1, *)
    private static let ios26_1AdditionalLanguages: Set<String> = [...]

    private static var supportedBCP47: Set<String> {
        var languages = ios26_0Languages
        if #available(iOS 26.1, *) {
            languages.formUnion(ios26_1AdditionalLanguages)
        }
        return languages
    }
}
```

### Fallback Strategy
```swift
static func suggestedFallback(for bcp47: String) -> String {
    if #available(iOS 26.1, *) {
        // iOS 26.1+: Use native language if available
        switch base {
        case "sv": return "sv-se"  // No fallback needed!
        case "da": return "da-dk"
        case "nl": return "nl-nl"
        // ...
        }
    }

    // iOS 26.0: Fallback to English
    switch base {
    case "sv", "da", "nl": return "en-gb"
    // ...
    }
}
```

## User Experience

### Scenario 1: Swedish User on iOS 26.0
1. Opens app, speaks Swedish
2. Language detected: `sv-se`
3. Banner appears: "Swedish not supported"
4. User chooses: "Use EN-GB for summaries"
5. Summary generated in English

### Scenario 2: Swedish User on iOS 26.1+
1. Opens app, speaks Swedish
2. Language detected: `sv-se`
3. **No banner** (Swedish is supported!)
4. Summary generated in Swedish ⭐

### Scenario 3: Turkish User on iOS 26.0
1. Opens app, speaks Turkish
2. Language detected: `tr-tr`
3. Banner appears: "Turkish not supported"
4. User chooses: "Use EN-GB for summaries"
5. Summary generated in English

### Scenario 4: Turkish User on iOS 26.1+
1. Opens app, speaks Turkish
2. Language detected: `tr-tr`
3. **No banner** (Turkish is supported!)
4. Summary generated in Turkish ⭐

## Testing Matrix

| Language | iOS 26.0 | iOS 26.1+ |
|----------|----------|-----------|
| English | ✅ Native | ✅ Native |
| French | ✅ Native | ✅ Native |
| German | ✅ Native | ✅ Native |
| Italian | ✅ Native | ✅ Native |
| Spanish | ✅ Native | ✅ Native |
| Portuguese (Brazil) | ✅ Native | ✅ Native |
| Portuguese (Portugal) | ⚠️ → pt-br | ✅ Native |
| Chinese (Simplified) | ✅ Native | ✅ Native |
| Chinese (Traditional) | ⚠️ → zh-hans | ✅ Native |
| Japanese | ✅ Native | ✅ Native |
| Korean | ✅ Native | ✅ Native |
| Swedish | ⚠️ → en-gb | ✅ Native |
| Danish | ⚠️ → en-gb | ✅ Native |
| Dutch | ⚠️ → en-gb | ✅ Native |
| Norwegian | ⚠️ → en-gb | ✅ Native |
| Turkish | ⚠️ → en-gb | ✅ Native |
| Vietnamese | ⚠️ → en-gb | ✅ Native |

Legend:
- ✅ Native: Supported natively, no fallback
- ⚠️ → fallback: Shows banner, offers fallback

## Portuguese Special Handling

### iOS 26.0:
```swift
pt-pt → pt-br  // Portugal Portuguese → Brazil Portuguese
pt-br → pt-br  // Brazil Portuguese → Brazil Portuguese
```

### iOS 26.1+:
```swift
pt-pt → pt-pt  // Portugal Portuguese → Portugal Portuguese ✓
pt-br → pt-br  // Brazil Portuguese → Brazil Portuguese ✓
```

Both variants now supported natively on 26.1+!

## Chinese Special Handling

### iOS 26.0:
```swift
zh-hans → zh-hans  // Simplified → Simplified ✓
zh-hant → zh-hans  // Traditional → Simplified (fallback)
zh-tw → zh-hans    // Taiwan → Simplified (fallback)
zh-hk → zh-hans    // Hong Kong → Simplified (fallback)
```

### iOS 26.1+:
```swift
zh-hans → zh-hans  // Simplified → Simplified ✓
zh-hant → zh-hant  // Traditional → Traditional ✓
zh-tw → zh-hant    // Taiwan → Traditional ✓
zh-hk → zh-hant    // Hong Kong → Traditional ✓
```

Both variants now supported natively on 26.1+!

## Norwegian Special Handling

### iOS 26.0:
```swift
nb-no → en-gb  // Bokmål → English (fallback)
nn-no → en-gb  // Nynorsk → English (fallback)
no → en-gb     // Generic Norwegian → English (fallback)
```

### iOS 26.1+:
```swift
nb-no → nb-no  // Bokmål → Bokmål ✓
nn-no → nb-no  // Nynorsk → Bokmål (default Norwegian)
no → nb-no     // Generic Norwegian → Bokmål
```

Bokmål is the default/primary Norwegian variant on 26.1+.

## Logging

### iOS 26.0:
```
Language detected: sv-se
Apple Intelligence support check: unsupported
Banner shown: Swedish → English fallback
```

### iOS 26.1+:
```
Language detected: sv-se
Apple Intelligence support check: supported
No banner needed (native support)
```

## Future-Proofing

When Apple adds more languages in future iOS versions (26.2, 27.0, etc.):

1. Add new version check:
```swift
@available(iOS 26.2, *)
private static let ios26_2AdditionalLanguages: Set<String> = [
    "ar-sa",  // Arabic
    "hi-in",  // Hindi
    // etc.
]
```

2. Update computed property:
```swift
private static var supportedBCP47: Set<String> {
    var languages = ios26_0Languages
    if #available(iOS 26.1, *) {
        languages.formUnion(ios26_1AdditionalLanguages)
    }
    if #available(iOS 26.2, *) {
        languages.formUnion(ios26_2AdditionalLanguages)
    }
    return languages
}
```

3. Update fallback logic:
```swift
if #available(iOS 26.2, *) {
    switch base {
    case "ar": return "ar-sa"
    case "hi": return "hi-in"
    // ...
    }
}
```

## ASR vs LLM Language

**Important:** ASR (speech recognition) and LLM (summary generation) use **different** language settings:

- **ASR Locale** (LiveTranscriber): What language to transcribe
  - Set via `LanguagePolicy.initialASRLocale()`
  - Defaults to `en_US`
  - User can override in CaptureView

- **LLM Output Locale** (Apple Intelligence): What language to generate summaries in
  - Checked via `LLMLanguageSupport.isSupported()`
  - Version-dependent (26.0 vs 26.1+)
  - User gets fallback option via banner

**Example:**
```
ASR: sv_SE (transcribe Swedish speech)
LLM (26.0): en-gb (generate English summary - fallback)
LLM (26.1): sv-se (generate Swedish summary - native)
```

This separation allows:
- Transcribing Swedish speech even on iOS 26.0
- Offering English summary fallback when Swedish LLM isn't available
- Using native Swedish summaries when iOS 26.1+ is available
