//
//  DiskManifest.swift
//  DiskSync
//
//  A small JSON manifest written to the destination drive (inside the
//  `.disksync-target` marker) so the drive "remembers" what it backs up. When
//  the same drive is reconnected on a fresh install, the app can re-adopt the
//  same folders.
//

import Foundation

nonisolated struct DiskManifest: Codable, Sendable {
    struct Source: Codable, Sendable {
        var path: String
        var isDirectory: Bool
        var enabled: Bool
    }

    var version: Int = 1
    var updatedAt: Date
    var deviceName: String
    var sources: [Source]
    var excludes: [String]
    var mirrorEnabled: Bool

    /// Read the manifest from a destination root's marker file (if present and
    /// JSON — older plain-text markers simply return nil).
    static func read(fromDestination root: URL) -> DiskManifest? {
        let url = root.appendingPathComponent(Defaults.markerFileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(DiskManifest.self, from: data)
    }

    /// Write the manifest to the destination root's marker file.
    func write(toDestination root: URL) {
        let url = root.appendingPathComponent(Defaults.markerFileName)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self) else { return }
        try? data.write(to: url)
    }
}
