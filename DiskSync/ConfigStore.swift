//
//  ConfigStore.swift
//  DiskSync
//
//  Higher-level configuration store: wraps the SQLite `Database` actor and
//  owns security-scoped bookmark creation / resolution. AppState talks to
//  this rather than to SQLite directly.
//

import Foundation

actor ConfigStore {
    let database: Database

    init() throws {
        database = try Database()
    }

    // MARK: - Settings

    func loadSettings() async throws -> AppSettings { try await database.loadSettings() }
    func saveSettings(_ s: AppSettings) async throws { try await database.saveSettings(s) }

    // MARK: - Sources

    func sources() async throws -> [Source] { try await database.fetchSources() }

    func addSource(url: URL) async throws -> Source {
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        let bookmark = ConfigStore.makeBookmark(for: url)
        return try await database.insertSource(bookmark: bookmark,
                                               displayName: url.lastPathComponent,
                                               path: url.path,
                                               isDirectory: isDir,
                                               enabled: true)
    }

    func setSourceEnabled(_ id: Int64, _ enabled: Bool) async throws {
        try await database.setSourceEnabled(id: id, enabled: enabled)
    }

    func removeSource(_ id: Int64) async throws { try await database.deleteSource(id: id) }

    // MARK: - Excludes

    func excludes() async throws -> [ExcludeRule] { try await database.fetchExcludes() }
    func addExclude(pattern: String, sourceId: Int64?) async throws -> ExcludeRule {
        try await database.insertExclude(pattern: pattern, enabled: true, sourceId: sourceId)
    }
    func updateExclude(_ rule: ExcludeRule) async throws { try await database.updateExclude(rule) }
    func removeExclude(_ id: Int64) async throws { try await database.deleteExclude(id: id) }

    // MARK: - History

    func recordRun(_ result: SyncRunResult) async throws { try await database.recordRun(result) }
    func recentRuns() async throws -> [SyncRun] { try await database.fetchRecentRuns() }
    func recentEvents() async throws -> [SyncEvent] { try await database.fetchRecentEvents() }

    // MARK: - Bookmarks (nonisolated: pure URL <-> Data helpers)

    /// Create a bookmark, preferring a security-scoped one but falling back to
    /// a plain bookmark when the entitlement is unavailable (non-sandboxed).
    nonisolated static func makeBookmark(for url: URL) -> Data? {
        if let data = try? url.bookmarkData(options: [.withSecurityScope],
                                            includingResourceValuesForKeys: nil,
                                            relativeTo: nil) {
            return data
        }
        return try? url.bookmarkData(options: [],
                                     includingResourceValuesForKeys: nil,
                                     relativeTo: nil)
    }

    /// Resolve a bookmark to a URL, starting security-scoped access when
    /// applicable. Returns nil if the bookmark cannot be resolved.
    nonisolated static func resolve(_ data: Data) -> URL? {
        var stale = false
        if let url = try? URL(resolvingBookmarkData: data,
                              options: [.withSecurityScope],
                              relativeTo: nil,
                              bookmarkDataIsStale: &stale) {
            _ = url.startAccessingSecurityScopedResource()
            return url
        }
        if let url = try? URL(resolvingBookmarkData: data,
                              options: [],
                              relativeTo: nil,
                              bookmarkDataIsStale: &stale) {
            return url
        }
        return nil
    }
}
