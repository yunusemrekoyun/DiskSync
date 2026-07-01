//
//  CloudStatus.swift
//  DiskSync
//
//  Best-effort iCloud Drive activity, using public URL resource keys
//  (.ubiquitousItemIsUploading / IsDownloading / DownloadingStatus). macOS's
//  exact Finder indicator is private; this scans the local iCloud Drive folder
//  (needs Full Disk Access), capped and only while the Sync tab is visible.
//

import Foundation

nonisolated struct CloudSnapshot: Sendable {
    var uploading = 0
    var downloading = 0
    var notDownloaded = 0
    var scanned = 0
    var capped = false
}

@MainActor
@Observable
final class CloudStatus {
    static let shared = CloudStatus()
    private init() {}

    var available = false
    var uploading = 0
    var downloading = 0
    var notDownloaded = 0
    var lastChecked: Date?

    private var scanning = false

    private static var driveURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
    }

    var isActive: Bool { uploading > 0 || downloading > 0 }

    var summary: String {
        guard available else { return "Off" }
        if uploading > 0 { return "Uploading \(uploading)" }
        if downloading > 0 { return "Downloading \(downloading)" }
        if notDownloaded > 0 { return "\(notDownloaded) not downloaded" }
        return "Up to date"
    }

    func refresh() async {
        let root = Self.driveURL
        guard FileManager.default.fileExists(atPath: root.path) else {
            available = false
            return
        }
        available = true
        guard !scanning else { return }
        scanning = true
        let snapshot = await Task.detached(priority: .utility) { CloudStatus.scan(root) }.value
        uploading = snapshot.uploading
        downloading = snapshot.downloading
        notDownloaded = snapshot.notDownloaded
        lastChecked = Date()
        scanning = false
    }

    /// Enumerate the iCloud Drive folder (capped) counting in-flight items.
    private nonisolated static func scan(_ root: URL) -> CloudSnapshot {
        let keys: [URLResourceKey] = [
            .isDirectoryKey,
            .ubiquitousItemIsUploadingKey,
            .ubiquitousItemIsDownloadingKey,
            .ubiquitousItemDownloadingStatusKey,
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }
        ) else { return CloudSnapshot() }

        var snap = CloudSnapshot()
        let cap = 12_000
        while let url = enumerator.nextObject() as? URL {
            snap.scanned += 1
            if snap.scanned > cap { snap.capped = true; break }
            guard let rv = try? url.resourceValues(forKeys: Set(keys)), rv.isDirectory != true else { continue }
            if rv.ubiquitousItemIsUploading == true { snap.uploading += 1 }
            if rv.ubiquitousItemIsDownloading == true { snap.downloading += 1 }
            if rv.ubiquitousItemDownloadingStatus == .notDownloaded { snap.notDownloaded += 1 }
        }
        return snap
    }
}
