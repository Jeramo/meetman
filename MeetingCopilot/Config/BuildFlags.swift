//
//  BuildFlags.swift
//  MeetingCopilot
//
//  Build-time feature flags for conditional compilation
//

import Foundation

#if DEBUG
/// Enable Apple Intelligence (Foundation Models) integration
/// Set to false to force heuristic summarizer for testing
public let BACKEND_AI: Bool = true

/// Enable iCloud sync for SwiftData container
public let ICLOUD_SYNC: Bool = false
#else
/// Production: Apple Intelligence enabled by default
public let BACKEND_AI: Bool = true

/// Production: iCloud sync disabled by default
public let ICLOUD_SYNC: Bool = false
#endif
