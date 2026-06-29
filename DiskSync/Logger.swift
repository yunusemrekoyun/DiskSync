//
//  Logger.swift
//  DiskSync
//
//  A tiny rolling text logger that backs the "Open Log" button. Per-file
//  sync outcomes are also written to SQLite (see Database / sync_events);
//  this file is the human-readable companion at
//  ~/Library/Application Support/DiskSync/sync.log
//

import Foundation

/// Thread-safe append-only text log. All writes are serialized on a private
/// queue so it is safe to call from any actor.
nonisolated final class AppLog: @unchecked Sendable {
    static let shared = AppLog()

    let fileURL: URL
    private let queue = DispatchQueue(label: "com.yunusemre.DiskSync.log")
    private let maxBytes: Int = 2 * 1024 * 1024   // rotate at ~2 MB

    init() {
        let dir = AppPaths.supportDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("sync.log")
    }

    func log(_ message: String) {
        queue.async { [fileURL, maxBytes] in
            let stamp = ISO8601DateFormatter().string(from: Date())
            let line = "[\(stamp)] \(message)\n"
            guard let data = line.data(using: .utf8) else { return }

            let fm = FileManager.default
            if !fm.fileExists(atPath: fileURL.path) {
                try? data.write(to: fileURL)
                return
            }

            // Rotate if the file has grown too large.
            if let size = (try? fm.attributesOfItem(atPath: fileURL.path)[.size] as? Int), size > maxBytes {
                let backup = fileURL.deletingPathExtension().appendingPathExtension("0.log")
                try? fm.removeItem(at: backup)
                try? fm.moveItem(at: fileURL, to: backup)
                try? data.write(to: fileURL)
                return
            }

            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            }
        }
    }
}

/// Shared, well-known on-disk locations.
nonisolated enum AppPaths {
    static var supportDirectory: URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                 in: .userDomainMask,
                                                 appropriateFor: nil,
                                                 create: true))
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("DiskSync", isDirectory: true)
    }

    static var databaseURL: URL {
        supportDirectory.appendingPathComponent("disksync.sqlite")
    }
}
