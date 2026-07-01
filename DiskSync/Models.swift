//
//  Models.swift
//  DiskSync
//
//  Core value types shared across the app. Everything here is a plain,
//  `Sendable` value type so it can travel freely between the MainActor
//  (UI) and the background actors (sync engine, database).
//

import Foundation

// MARK: - Status

/// High-level state of the sync engine, surfaced in the menu-bar badge.
nonisolated enum SyncStatus: Sendable, Equatable {
    case idle              // green  – everything mirrored, drive present
    case syncing           // blue   – a run is in progress
    case paused            // amber  – destination drive disconnected
    case error(String)     // red    – last run reported errors

    var isError: Bool {
        if case .error = self { return true }
        return false
    }
}

/// The outcome recorded for an individual file during a run.
nonisolated enum SyncEventType: String, Sendable, Codable, CaseIterable {
    case copied     // brand new file written to the destination
    case updated    // existing file overwritten because source changed
    case skipped    // up-to-date / excluded – usually not persisted
    case conflict   // destination was newer, overwritten anyway (source-of-truth)
    case error      // could not copy (busy / permission / disk full)
}

// MARK: - Sources & Excludes

/// A user-selected file or folder to mirror. The list starts empty.
nonisolated struct Source: Identifiable, Sendable, Hashable {
    var id: Int64
    var bookmark: Data?
    var displayName: String
    var path: String
    var isDirectory: Bool
    var enabled: Bool
    var addedAt: Date

    var url: URL { URL(fileURLWithPath: path) }
}

/// A within-folder exclusion rule (glob / name). `sourceId == nil` ⇒ global.
nonisolated struct ExcludeRule: Identifiable, Sendable, Hashable {
    var id: Int64
    var pattern: String
    var enabled: Bool
    var sourceId: Int64?
}

// MARK: - History

/// One sync run (full reconcile or incremental).
nonisolated struct SyncRun: Identifiable, Sendable, Hashable {
    var id: Int64
    var startedAt: Date
    var finishedAt: Date?
    var status: String
    var filesCopied: Int
    var bytesCopied: Int64
    var errorsCount: Int
    var summary: String
}

/// A file that mirror-mode moved into the on-drive archive (recoverable).
nonisolated struct ArchivedItem: Identifiable, Sendable, Hashable {
    var id: Int64
    var relativePath: String        // original home-relative path (where to restore)
    var archivePath: String         // path inside the archive folder
    var deletedAt: Date
    var bytes: Int64
    var sourceId: Int64?

    var name: String { (relativePath as NSString).lastPathComponent }
}

/// One per-file event inside a run.
nonisolated struct SyncEvent: Identifiable, Sendable, Hashable {
    var id: Int64
    var runId: Int64
    var timestamp: Date
    var type: SyncEventType
    var relativePath: String
    var sourceId: Int64?
    var message: String
}

// MARK: - Settings

/// The single-row application settings.
nonisolated struct AppSettings: Sendable, Equatable {
    var destinationBookmark: Data?
    var destinationPath: String
    var syncIntervalMinutes: Int
    var autoSyncEnabled: Bool
    var runAtLogin: Bool
    var notificationsEnabled: Bool
    /// Mirror mode: reflect deletions/moves on the drive by relocating removed
    /// items into the on-drive archive (never a hard delete). Off by default.
    var mirrorEnabled: Bool

    static let `default` = AppSettings(
        destinationBookmark: nil,
        destinationPath: "/Volumes/MetalMini/PC-Sync",
        syncIntervalMinutes: 15,
        autoSyncEnabled: true,
        runAtLogin: false,
        notificationsEnabled: true,
        mirrorEnabled: false
    )
}

// MARK: - Live progress

/// Live progress published by the engine during a run.
nonisolated struct SyncProgress: Sendable, Equatable {
    var filesProcessed: Int
    var filesTotalEstimate: Int
    var currentPath: String

    var fraction: Double {
        guard filesTotalEstimate > 0 else { return 0 }
        return min(1, Double(filesProcessed) / Double(filesTotalEstimate))
    }
}

// MARK: - Drive info

/// Snapshot of the destination volume's capacity.
nonisolated struct DriveInfo: Sendable, Equatable {
    var isConnected: Bool
    var volumeName: String
    var totalBytes: Int64
    var freeBytes: Int64

    var usedBytes: Int64 { max(0, totalBytes - freeBytes) }

    static let disconnected = DriveInfo(isConnected: false, volumeName: "", totalBytes: 0, freeBytes: 0)
}

// MARK: - Suggested quick-adds (section 9). These are NOT auto-added.

nonisolated struct SuggestedItem: Identifiable, Sendable, Hashable {
    var relativePath: String   // relative to the user's home
    var isDirectory: Bool
    var id: String { relativePath }

    /// Resolved absolute URL under the current user's home directory.
    var url: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(relativePath)
    }
}

nonisolated enum Defaults {
    /// The marker file written at the destination root to confirm the target.
    /// Also holds the JSON config manifest (so the drive "remembers" its setup).
    static let markerFileName = ".disksync-target"

    /// On-drive archive folder where mirror mode relocates removed items.
    static let archiveFolderName = ".DiskSync-Archive"

    /// Suggested folders/files offered as one-tap quick-adds.
    static let suggested: [SuggestedItem] = [
        SuggestedItem(relativePath: "Works", isDirectory: true),
        SuggestedItem(relativePath: "Downloads", isDirectory: true),
        SuggestedItem(relativePath: ".zprofile", isDirectory: false),
        SuggestedItem(relativePath: ".gitconfig", isDirectory: false),
        SuggestedItem(relativePath: ".zsh_history", isDirectory: false),
        SuggestedItem(relativePath: ".config", isDirectory: true),
        SuggestedItem(relativePath: ".ssh", isDirectory: true),
        SuggestedItem(relativePath: ".claude/projects", isDirectory: true),
        SuggestedItem(relativePath: "Library/Application Support/Claude/local-agent-mode-sessions", isDirectory: true),
    ]

    /// Default exclude patterns seeded on first run.
    static let excludes: [String] = ["node_modules", ".DS_Store"]
}
