//
//  BuildFlags.swift
//  MeetingCopilot
//
//  Build-time feature flags for conditional compilation
//

import Foundation

#if DEBUG
/// Enable iCloud sync for SwiftData container
public let ICLOUD_SYNC: Bool = false
#else
/// Production: iCloud sync disabled by default
public let ICLOUD_SYNC: Bool = false
#endif

/// Transcription locale (deprecated - now handled by LanguagePolicy)
/// ASR locale is chosen automatically or via user selection in CaptureView
/// See: ASR/LanguagePolicy.swift
@available(*, deprecated, message: "Use LanguagePolicy.initialASRLocale() instead")
public let TRANSCRIPTION_LOCALE: String = "en_US"
