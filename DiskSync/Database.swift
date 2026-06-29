//
//  Database.swift
//  DiskSync
//
//  A small actor wrapping the system SQLite3 C API (the copy that ships with
//  macOS — `import SQLite3`). No third-party dependencies. All access is
//  serialized through the actor, so the raw `OpaquePointer` never escapes.
//

import Foundation
import SQLite3

// SQLite wants to know whether a bound buffer is transient (it should copy it).
// `nonisolated(unsafe)` keeps this file-scope constant out of the default
// MainActor isolation so the Database actor can reference it freely.
private nonisolated(unsafe) let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum DatabaseError: Error, CustomStringConvertible {
    case open(String)
    case prepare(String)
    case step(String)
    case exec(String)

    var description: String {
        switch self {
        case .open(let m): return "sqlite open failed: \(m)"
        case .prepare(let m): return "sqlite prepare failed: \(m)"
        case .step(let m): return "sqlite step failed: \(m)"
        case .exec(let m): return "sqlite exec failed: \(m)"
        }
    }
}

actor Database {
    // `nonisolated(unsafe)`: every real access happens inside an actor method
    // (so it's serialized); this only lets `deinit` close the handle.
    private nonisolated(unsafe) var db: OpaquePointer?

    /// Keep at most this many events so the table never grows unbounded.
    private let maxEvents = 2_000

    init() throws {
        let url = AppPaths.databaseURL
        try? FileManager.default.createDirectory(at: AppPaths.supportDirectory,
                                                 withIntermediateDirectories: true)
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK, let handle else {
            let msg = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            throw DatabaseError.open(msg)
        }
        db = handle
        sqlite3_exec(handle, "PRAGMA journal_mode=WAL;", nil, nil, nil)
        sqlite3_exec(handle, "PRAGMA foreign_keys=ON;", nil, nil, nil)
        try Database.migrate(handle)
    }

    deinit {
        if let db { sqlite3_close_v2(db) }
    }

    // MARK: - Low-level helpers

    private func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(err)
            throw DatabaseError.exec(msg)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw DatabaseError.prepare(String(cString: sqlite3_errmsg(db)))
        }
        return stmt
    }

    private func bind(_ stmt: OpaquePointer, _ idx: Int32, _ value: String?) {
        if let value { sqlite3_bind_text(stmt, idx, value, -1, SQLITE_TRANSIENT) }
        else { sqlite3_bind_null(stmt, idx) }
    }

    private func bind(_ stmt: OpaquePointer, _ idx: Int32, _ value: Int64) {
        sqlite3_bind_int64(stmt, idx, value)
    }

    private func bind(_ stmt: OpaquePointer, _ idx: Int32, _ value: Double) {
        sqlite3_bind_double(stmt, idx, value)
    }

    private func bind(_ stmt: OpaquePointer, _ idx: Int32, _ value: Bool) {
        sqlite3_bind_int(stmt, idx, value ? 1 : 0)
    }

    private func bind(_ stmt: OpaquePointer, _ idx: Int32, _ data: Data?) {
        if let data {
            data.withUnsafeBytes { raw in
                sqlite3_bind_blob(stmt, idx, raw.baseAddress, Int32(data.count), SQLITE_TRANSIENT)
            }
        } else {
            sqlite3_bind_null(stmt, idx)
        }
    }

    private func bindOptionalInt(_ stmt: OpaquePointer, _ idx: Int32, _ value: Int64?) {
        if let value { sqlite3_bind_int64(stmt, idx, value) }
        else { sqlite3_bind_null(stmt, idx) }
    }

    private func columnText(_ stmt: OpaquePointer, _ idx: Int32) -> String {
        guard let c = sqlite3_column_text(stmt, idx) else { return "" }
        return String(cString: c)
    }

    private func columnData(_ stmt: OpaquePointer, _ idx: Int32) -> Data? {
        guard let ptr = sqlite3_column_blob(stmt, idx) else { return nil }
        let len = Int(sqlite3_column_bytes(stmt, idx))
        return len > 0 ? Data(bytes: ptr, count: len) : nil
    }

    private func columnOptionalInt(_ stmt: OpaquePointer, _ idx: Int32) -> Int64? {
        if sqlite3_column_type(stmt, idx) == SQLITE_NULL { return nil }
        return sqlite3_column_int64(stmt, idx)
    }

    // MARK: - Migrations

    /// Runs the schema on the freshly-opened handle. Static + nonisolated so it
    /// can be called from the actor's (nonisolated) initializer.
    private nonisolated static func migrate(_ db: OpaquePointer) throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS settings (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            destinationBookmark BLOB,
            destinationPath TEXT NOT NULL,
            syncIntervalMinutes INTEGER NOT NULL,
            autoSyncEnabled INTEGER NOT NULL,
            runAtLogin INTEGER NOT NULL,
            notificationsEnabled INTEGER NOT NULL,
            schemaVersion INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS sources (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            bookmark BLOB,
            displayName TEXT NOT NULL,
            path TEXT NOT NULL,
            isDirectory INTEGER NOT NULL,
            enabled INTEGER NOT NULL,
            addedAt REAL NOT NULL
        );
        CREATE TABLE IF NOT EXISTS excludes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            pattern TEXT NOT NULL,
            enabled INTEGER NOT NULL,
            sourceId INTEGER
        );
        CREATE TABLE IF NOT EXISTS sync_runs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            startedAt REAL NOT NULL,
            finishedAt REAL,
            status TEXT NOT NULL,
            filesCopied INTEGER NOT NULL,
            bytesCopied INTEGER NOT NULL,
            errorsCount INTEGER NOT NULL,
            summary TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS sync_events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            runId INTEGER NOT NULL,
            timestamp REAL NOT NULL,
            type TEXT NOT NULL,
            relativePath TEXT NOT NULL,
            sourceId INTEGER,
            message TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_events_ts ON sync_events(timestamp DESC);
        """
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(err)
            throw DatabaseError.exec(msg)
        }
    }

    // MARK: - Settings

    func loadSettings() throws -> AppSettings {
        let stmt = try prepare("""
        SELECT destinationBookmark, destinationPath, syncIntervalMinutes,
               autoSyncEnabled, runAtLogin, notificationsEnabled
        FROM settings WHERE id = 1;
        """)
        defer { sqlite3_finalize(stmt) }

        if sqlite3_step(stmt) == SQLITE_ROW {
            return AppSettings(
                destinationBookmark: columnData(stmt, 0),
                destinationPath: columnText(stmt, 1),
                syncIntervalMinutes: Int(sqlite3_column_int(stmt, 2)),
                autoSyncEnabled: sqlite3_column_int(stmt, 3) != 0,
                runAtLogin: sqlite3_column_int(stmt, 4) != 0,
                notificationsEnabled: sqlite3_column_int(stmt, 5) != 0
            )
        }

        // First launch: seed defaults.
        try saveSettings(.default)
        try seedDefaultExcludesIfEmpty()
        return .default
    }

    func saveSettings(_ s: AppSettings) throws {
        let stmt = try prepare("""
        INSERT INTO settings
            (id, destinationBookmark, destinationPath, syncIntervalMinutes,
             autoSyncEnabled, runAtLogin, notificationsEnabled, schemaVersion)
        VALUES (1, ?, ?, ?, ?, ?, ?, 1)
        ON CONFLICT(id) DO UPDATE SET
            destinationBookmark = excluded.destinationBookmark,
            destinationPath = excluded.destinationPath,
            syncIntervalMinutes = excluded.syncIntervalMinutes,
            autoSyncEnabled = excluded.autoSyncEnabled,
            runAtLogin = excluded.runAtLogin,
            notificationsEnabled = excluded.notificationsEnabled;
        """)
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, s.destinationBookmark)
        bind(stmt, 2, s.destinationPath)
        bind(stmt, 3, Int64(s.syncIntervalMinutes))
        bind(stmt, 4, s.autoSyncEnabled)
        bind(stmt, 5, s.runAtLogin)
        bind(stmt, 6, s.notificationsEnabled)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.step(String(cString: sqlite3_errmsg(db)))
        }
    }

    // MARK: - Sources

    func fetchSources() throws -> [Source] {
        let stmt = try prepare("""
        SELECT id, bookmark, displayName, path, isDirectory, enabled, addedAt
        FROM sources ORDER BY addedAt ASC;
        """)
        defer { sqlite3_finalize(stmt) }
        var result: [Source] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            result.append(Source(
                id: sqlite3_column_int64(stmt, 0),
                bookmark: columnData(stmt, 1),
                displayName: columnText(stmt, 2),
                path: columnText(stmt, 3),
                isDirectory: sqlite3_column_int(stmt, 4) != 0,
                enabled: sqlite3_column_int(stmt, 5) != 0,
                addedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 6))
            ))
        }
        return result
    }

    @discardableResult
    func insertSource(bookmark: Data?, displayName: String, path: String,
                      isDirectory: Bool, enabled: Bool) throws -> Source {
        let stmt = try prepare("""
        INSERT INTO sources (bookmark, displayName, path, isDirectory, enabled, addedAt)
        VALUES (?, ?, ?, ?, ?, ?);
        """)
        defer { sqlite3_finalize(stmt) }
        let now = Date()
        bind(stmt, 1, bookmark)
        bind(stmt, 2, displayName)
        bind(stmt, 3, path)
        bind(stmt, 4, isDirectory)
        bind(stmt, 5, enabled)
        bind(stmt, 6, now.timeIntervalSince1970)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.step(String(cString: sqlite3_errmsg(db)))
        }
        let id = sqlite3_last_insert_rowid(db)
        return Source(id: id, bookmark: bookmark, displayName: displayName, path: path,
                      isDirectory: isDirectory, enabled: enabled, addedAt: now)
    }

    func setSourceEnabled(id: Int64, enabled: Bool) throws {
        let stmt = try prepare("UPDATE sources SET enabled = ? WHERE id = ?;")
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, enabled)
        bind(stmt, 2, id)
        _ = sqlite3_step(stmt)
    }

    func deleteSource(id: Int64) throws {
        let stmt = try prepare("DELETE FROM sources WHERE id = ?;")
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, id)
        _ = sqlite3_step(stmt)
    }

    // MARK: - Excludes

    private func seedDefaultExcludesIfEmpty() throws {
        let countStmt = try prepare("SELECT COUNT(*) FROM excludes;")
        defer { sqlite3_finalize(countStmt) }
        guard sqlite3_step(countStmt) == SQLITE_ROW, sqlite3_column_int(countStmt, 0) == 0 else { return }
        for pattern in Defaults.excludes {
            _ = try insertExclude(pattern: pattern, enabled: true, sourceId: nil)
        }
    }

    func fetchExcludes() throws -> [ExcludeRule] {
        let stmt = try prepare("SELECT id, pattern, enabled, sourceId FROM excludes ORDER BY id ASC;")
        defer { sqlite3_finalize(stmt) }
        var result: [ExcludeRule] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            result.append(ExcludeRule(
                id: sqlite3_column_int64(stmt, 0),
                pattern: columnText(stmt, 1),
                enabled: sqlite3_column_int(stmt, 2) != 0,
                sourceId: columnOptionalInt(stmt, 3)
            ))
        }
        return result
    }

    @discardableResult
    func insertExclude(pattern: String, enabled: Bool, sourceId: Int64?) throws -> ExcludeRule {
        let stmt = try prepare("INSERT INTO excludes (pattern, enabled, sourceId) VALUES (?, ?, ?);")
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, pattern)
        bind(stmt, 2, enabled)
        bindOptionalInt(stmt, 3, sourceId)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.step(String(cString: sqlite3_errmsg(db)))
        }
        return ExcludeRule(id: sqlite3_last_insert_rowid(db), pattern: pattern,
                           enabled: enabled, sourceId: sourceId)
    }

    func updateExclude(_ rule: ExcludeRule) throws {
        let stmt = try prepare("UPDATE excludes SET pattern = ?, enabled = ?, sourceId = ? WHERE id = ?;")
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, rule.pattern)
        bind(stmt, 2, rule.enabled)
        bindOptionalInt(stmt, 3, rule.sourceId)
        bind(stmt, 4, rule.id)
        _ = sqlite3_step(stmt)
    }

    func deleteExclude(id: Int64) throws {
        let stmt = try prepare("DELETE FROM excludes WHERE id = ?;")
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, id)
        _ = sqlite3_step(stmt)
    }

    // MARK: - Runs & events

    /// Persist a finished run plus its per-file events, then prune.
    @discardableResult
    func recordRun(_ result: SyncRunResult) throws -> Int64 {
        let runStmt = try prepare("""
        INSERT INTO sync_runs (startedAt, finishedAt, status, filesCopied, bytesCopied, errorsCount, summary)
        VALUES (?, ?, ?, ?, ?, ?, ?);
        """)
        bind(runStmt, 1, result.startedAt.timeIntervalSince1970)
        bind(runStmt, 2, result.finishedAt.timeIntervalSince1970)
        bind(runStmt, 3, result.status)
        bind(runStmt, 4, Int64(result.filesCopied))
        bind(runStmt, 5, result.bytesCopied)
        bind(runStmt, 6, Int64(result.errorsCount))
        bind(runStmt, 7, result.summary)
        let ok = sqlite3_step(runStmt) == SQLITE_DONE
        sqlite3_finalize(runStmt)
        guard ok else { throw DatabaseError.step(String(cString: sqlite3_errmsg(db))) }
        let runId = sqlite3_last_insert_rowid(db)

        if !result.events.isEmpty {
            try exec("BEGIN TRANSACTION;")
            let evStmt = try prepare("""
            INSERT INTO sync_events (runId, timestamp, type, relativePath, sourceId, message)
            VALUES (?, ?, ?, ?, ?, ?);
            """)
            for ev in result.events {
                sqlite3_reset(evStmt)
                bind(evStmt, 1, runId)
                bind(evStmt, 2, ev.timestamp.timeIntervalSince1970)
                bind(evStmt, 3, ev.type.rawValue)
                bind(evStmt, 4, ev.relativePath)
                bindOptionalInt(evStmt, 5, ev.sourceId)
                bind(evStmt, 6, ev.message)
                _ = sqlite3_step(evStmt)
            }
            sqlite3_finalize(evStmt)
            try exec("COMMIT;")
        }

        try pruneEvents()
        return runId
    }

    private func pruneEvents() throws {
        // Keep the most recent `maxEvents` rows and anything < 30 days old.
        let cutoff = Date().addingTimeInterval(-30 * 24 * 3600).timeIntervalSince1970
        let stmt = try prepare("""
        DELETE FROM sync_events
        WHERE timestamp < ?
           OR id NOT IN (SELECT id FROM sync_events ORDER BY id DESC LIMIT ?);
        """)
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, cutoff)
        bind(stmt, 2, Int64(maxEvents))
        _ = sqlite3_step(stmt)
    }

    func fetchRecentRuns(limit: Int = 50) throws -> [SyncRun] {
        let stmt = try prepare("""
        SELECT id, startedAt, finishedAt, status, filesCopied, bytesCopied, errorsCount, summary
        FROM sync_runs ORDER BY startedAt DESC LIMIT ?;
        """)
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, Int64(limit))
        var result: [SyncRun] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let finished = sqlite3_column_type(stmt, 2) == SQLITE_NULL
                ? nil : Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2))
            result.append(SyncRun(
                id: sqlite3_column_int64(stmt, 0),
                startedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1)),
                finishedAt: finished,
                status: columnText(stmt, 3),
                filesCopied: Int(sqlite3_column_int(stmt, 4)),
                bytesCopied: sqlite3_column_int64(stmt, 5),
                errorsCount: Int(sqlite3_column_int(stmt, 6)),
                summary: columnText(stmt, 7)
            ))
        }
        return result
    }

    func fetchRecentEvents(limit: Int = 300) throws -> [SyncEvent] {
        let stmt = try prepare("""
        SELECT id, runId, timestamp, type, relativePath, sourceId, message
        FROM sync_events ORDER BY timestamp DESC, id DESC LIMIT ?;
        """)
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, Int64(limit))
        var result: [SyncEvent] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            result.append(SyncEvent(
                id: sqlite3_column_int64(stmt, 0),
                runId: sqlite3_column_int64(stmt, 1),
                timestamp: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2)),
                type: SyncEventType(rawValue: columnText(stmt, 3)) ?? .error,
                relativePath: columnText(stmt, 4),
                sourceId: columnOptionalInt(stmt, 5),
                message: columnText(stmt, 6)
            ))
        }
        return result
    }
}
