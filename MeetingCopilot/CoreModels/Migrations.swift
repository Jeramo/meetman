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
    // Future versions:
    // case v2 = "1.1.0"
}

/// Migration plans for schema evolution
public struct MigrationPlan {
    // When schema changes are needed, define migration plans here
    // Example:
    // static let v1ToV2 = SchemaMigrationPlan(
    //     sourceSchema: SchemaV1.self,
    //     destinationSchema: SchemaV2.self,
    //     mappings: [...]
    // )

    /// Currently we're on v1 with no migrations needed
    public static var current: SchemaVersion {
        .v1
    }
}
