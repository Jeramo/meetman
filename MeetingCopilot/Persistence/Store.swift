//
//  Store.swift
//  MeetingCopilot
//
//  SwiftData model container and configuration
//

import Foundation
import SwiftData
import OSLog

private let logger = Logger(subsystem: "com.jeramo.meetingman", category: "persistence")

/// SwiftData container manager
public final class Store: @unchecked Sendable {

    public static let shared = Store()

    public let container: ModelContainer

    private init() {
        do {
            let schema = Schema([
                Meeting.self,
                TranscriptChunk.self,
                Decision.self
            ])

            let configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                allowsSave: true,
                cloudKitDatabase: FeatureGates.iCloudEnabled ? .automatic : .none
            )

            container = try ModelContainer(
                for: schema,
                configurations: [configuration]
            )

            logger.info("Initialized SwiftData container (iCloud: \(FeatureGates.iCloudEnabled))")
        } catch {
            logger.error("Failed to initialize container: \(error.localizedDescription)")
            fatalError("Failed to initialize SwiftData container: \(error)")
        }
    }

    /// Main context for UI operations
    @MainActor
    public var mainContext: ModelContext {
        container.mainContext
    }

    /// Create background context for async operations
    public func backgroundContext() -> ModelContext {
        let context = ModelContext(container)
        context.autosaveEnabled = true
        return context
    }
}

// MARK: - Convenience Extensions

extension ModelContext {
    /// Save changes and log errors
    public func saveChanges() throws {
        guard hasChanges else { return }

        do {
            try save()
            logger.debug("Saved changes to model context")
        } catch {
            logger.error("Failed to save context: \(error.localizedDescription)")
            throw PersistenceError.saveFailed(underlying: error)
        }
    }

    /// Fetch with predicate helper
    public func fetch<T: PersistentModel>(
        _ type: T.Type,
        predicate: Predicate<T>? = nil,
        sortBy: [SortDescriptor<T>] = []
    ) throws -> [T] {
        var descriptor = FetchDescriptor<T>(predicate: predicate, sortBy: sortBy)
        descriptor.fetchLimit = nil

        do {
            return try fetch(descriptor)
        } catch {
            logger.error("Fetch failed for \(String(describing: type)): \(error.localizedDescription)")
            throw PersistenceError.fetchFailed(underlying: error)
        }
    }
}
