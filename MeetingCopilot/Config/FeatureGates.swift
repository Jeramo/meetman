//
//  FeatureGates.swift
//  MeetingCopilot
//
//  Runtime feature availability checks
//

import Foundation

/// Central source of truth for feature availability
public struct FeatureGates {

    /// Whether Apple Intelligence (Foundation Models) is available
    /// Checks runtime availability for iOS 26+ and FoundationModels framework
    public static var aiEnabled: Bool {
        if #available(iOS 26, *) {
            // Check if FoundationModels framework is actually available
            #if canImport(FoundationModels)
            return true
            #else
            return false
            #endif
        } else {
            return false
        }
    }

    /// Whether iCloud sync is enabled
    public static var iCloudEnabled: Bool {
        #if ICLOUD_SYNC
        return true
        #else
        return false
        #endif
    }

    /// Whether background processing is available
    @available(iOS 26, *)
    public static var backgroundProcessingAvailable: Bool {
        return true
    }
}
