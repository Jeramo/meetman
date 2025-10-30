//
//  Migrations.swift
//  MeetingCopilot
//
//  SwiftData schema migrations
//

import Foundation
import SwiftData

/// Schema version history
public enum SchemaVersion: String, CaseIterable {
    case v1 = "1.0.0"
    case v2 = "1.1.0" // Added speakerID to TranscriptChunk for diarization support
}

/// Migration plans for schema evolution
public struct MigrationPlan {
    // Note: SwiftData automatically handles additive schema changes (adding optional fields)
    // No explicit migration needed for v1 → v2 (speakerID is optional)
    //
    // When breaking schema changes are needed, define migration plans here
    // Example:
    // static let v1ToV2 = SchemaMigrationPlan(
    //     sourceSchema: SchemaV1.self,
    //     destinationSchema: SchemaV2.self,
    //     mappings: [...]
    // )

    /// Current schema version
    public static var current: SchemaVersion {
        .v2
    }
}
