//
//  SyncManager.swift
//  DiskSync
//
//  The native, FileManager-based one-way/additive sync engine. An actor
//  serializes runs (no two overlap), coalesces queued requests (latest wins),
//  and publishes live progress through an AsyncStream. Heavy file I/O runs in
//  a detached, low-priority task so the UI is never blocked.
//

import Foundation

// MARK: - Engine inputs / outputs (all Sendable value types)

/// A source resolved to a concrete URL plus its path relative to home, used to
/// mirror the home-directory structure under the destination root.
nonisolated struct ResolvedSource: Sendable {
    let id: Int64
    let url: URL
    let isDirectory: Bool
    let homeRelativePath: String
}

/// One unit of work handed to the engine.
nonisolated struct SyncRequest: Sendable {
    var sources: [ResolvedSource]
    var destinationRoot: URL
    var excludes: [ExcludeRule]
    var isFull: Bool
}

/// A per-file event captured during a run (persisted to SQLite afterwards).
nonisolated struct PendingEvent: Sendable {
    var timestamp: Date
    var type: SyncEventType
    var relativePath: String
    var sourceId: Int64?
    var message: String
}

/// The result of a completed run.
nonisolated struct SyncRunResult: Sendable {
    var startedAt: Date
    var finishedAt: Date
    var status: String
    var filesCopied: Int          // copied + updated
    var bytesCopied: Int64
    var errorsCount: Int
    var conflicts: Int
    var skipped: Int
    var isFull: Bool
    var events: [PendingEvent]

    var summary: String {
        var parts = ["\(filesCopied) file(s)", ByteCountFormatter.string(fromByteCount: bytesCopied, countStyle: .file)]
        if conflicts > 0 { parts.append("\(conflicts) conflict(s)") }
        if errorsCount > 0 { parts.append("\(errorsCount) error(s)") }
        return parts.joined(separator: " · ")
    }
}

/// Events streamed to the UI during the engine's lifetime.
nonisolated enum SyncManagerEvent: Sendable {
    case started
    case progress(SyncProgress)
    case finished(SyncRunResult)
    case idle
}

// MARK: - Engine

actor SyncManager {
    nonisolated let events: AsyncStream<SyncManagerEvent>
    private nonisolated let continuation: AsyncStream<SyncManagerEvent>.Continuation

    private var pending: SyncRequest?
    private var draining = false

    init() {
        var cont: AsyncStream<SyncManagerEvent>.Continuation!
        events = AsyncStream(bufferingPolicy: .bufferingNewest(64)) { cont = $0 }
        continuation = cont
    }

    /// Queue a run. If one is in flight, the new request is merged in
    /// (latest config wins, source sets unioned, full beats incremental).
    func enqueue(_ request: SyncRequest) {
        pending = SyncManager.merge(pending, request)
        guard !draining else { return }
        draining = true
        let cont = continuation
        // The heavy file I/O runs in this detached task (a background thread),
        // not on the actor's executor, so the actor stays responsive and new
        // requests can be coalesced while a run is in flight.
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            cont.yield(.started)
            while let request = await self.nextOrFinish() {
                let result = SyncManager.performSync(request) { progress in
                    cont.yield(.progress(progress))
                }
                cont.yield(.finished(result))
            }
            cont.yield(.idle)
        }
    }

    /// Returns the next coalesced request, or nil — clearing the `draining`
    /// flag atomically on the actor so there is no gap where a late enqueue
    /// could be lost.
    private func nextOrFinish() -> SyncRequest? {
        if let next = pending {
            pending = nil
            return next
        }
        draining = false
        return nil
    }

    /// Merge two requests: union sources by id, "full" wins, latest dest/excludes.
    private nonisolated static func merge(_ existing: SyncRequest?, _ new: SyncRequest) -> SyncRequest {
        guard let existing else { return new }
        var byID: [Int64: ResolvedSource] = [:]
        for s in existing.sources { byID[s.id] = s }
        for s in new.sources { byID[s.id] = s }
        return SyncRequest(sources: Array(byID.values),
                           destinationRoot: new.destinationRoot,
                           excludes: new.excludes,
                           isFull: existing.isFull || new.isFull)
    }

    // MARK: - Core algorithm (nonisolated: pure file work, no actor state)

    private nonisolated static func performSync(_ request: SyncRequest,
                                    progress: @Sendable (SyncProgress) -> Void) -> SyncRunResult {
        let started = Date()
        let fm = FileManager.default
        let log = AppLog.shared

        var copied = 0, updated = 0, skipped = 0, conflicts = 0, errors = 0
        var bytes: Int64 = 0
        var events: [PendingEvent] = []

        // Estimate total file count for the progress bar.
        let total = request.sources.reduce(0) { $0 + countFiles(source: $1, excludes: request.excludes, fm: fm) }
        var processed = 0
        progress(SyncProgress(filesProcessed: 0, filesTotalEstimate: total, currentPath: ""))

        log.log("Sync started (\(request.isFull ? "full reconcile" : "incremental"), \(request.sources.count) source(s), ~\(total) files)")

        func record(_ type: SyncEventType, _ rel: String, _ sourceId: Int64?, _ message: String) {
            events.append(PendingEvent(timestamp: Date(), type: type, relativePath: rel, sourceId: sourceId, message: message))
        }

        for source in request.sources {
            let destBase = request.destinationRoot.appendingPathComponent(source.homeRelativePath)

            if source.isDirectory {
                let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
                guard let enumerator = fm.enumerator(at: source.url,
                                                     includingPropertiesForKeys: Array(keys),
                                                     options: [],
                                                     errorHandler: { url, error in
                                                         log.log("Enumerate error at \(url.path): \(error.localizedDescription)")
                                                         return true
                                                     }) else { continue }

                while let item = enumerator.nextObject() as? URL {
                    let rv = try? item.resourceValues(forKeys: keys)
                    let isDir = rv?.isDirectory ?? false
                    let isLink = rv?.isSymbolicLink ?? false
                    let relWithin = relativePath(of: item, base: source.url)
                    let displayRel = source.homeRelativePath + "/" + relWithin

                    // Excludes: match by name or any relative-path component.
                    if matchesExclude(name: item.lastPathComponent, relPath: relWithin,
                                      excludes: request.excludes, sourceId: source.id) {
                        if isDir { enumerator.skipDescendants() }
                        skipped += 1
                        continue
                    }

                    let destURL = destBase.appendingPathComponent(relWithin)

                    if isLink {
                        copySymlink(from: item, to: destURL, fm: fm) { type, msg in
                            if type == .error { errors += 1 } else if type == .copied { copied += 1 }
                            record(type, displayRel, source.id, msg)
                        }
                    } else if isDir {
                        try? fm.createDirectory(at: destURL, withIntermediateDirectories: true)
                    } else {
                        let outcome = copyFileIfNeeded(from: item, to: destURL, srcValues: rv, fm: fm, log: log)
                        apply(outcome, rel: displayRel, sourceId: source.id,
                              copied: &copied, updated: &updated, skipped: &skipped,
                              conflicts: &conflicts, errors: &errors, bytes: &bytes, record: record)
                    }

                    processed += 1
                    if processed % 25 == 0 {
                        progress(SyncProgress(filesProcessed: processed, filesTotalEstimate: max(total, processed), currentPath: displayRel))
                    }
                }
            } else {
                // Single-file source.
                let rv = try? source.url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isSymbolicLinkKey])
                if rv?.isSymbolicLink == true {
                    copySymlink(from: source.url, to: destBase, fm: fm) { type, msg in
                        if type == .error { errors += 1 } else if type == .copied { copied += 1 }
                        record(type, source.homeRelativePath, source.id, msg)
                    }
                } else {
                    let outcome = copyFileIfNeeded(from: source.url, to: destBase, srcValues: rv, fm: fm, log: log)
                    apply(outcome, rel: source.homeRelativePath, sourceId: source.id,
                          copied: &copied, updated: &updated, skipped: &skipped,
                          conflicts: &conflicts, errors: &errors, bytes: &bytes, record: record)
                }
                processed += 1
            }
        }

        progress(SyncProgress(filesProcessed: processed, filesTotalEstimate: max(total, processed), currentPath: ""))

        let status = errors > 0 ? "completed_with_errors" : "completed"
        let result = SyncRunResult(startedAt: started, finishedAt: Date(), status: status,
                                   filesCopied: copied + updated, bytesCopied: bytes,
                                   errorsCount: errors, conflicts: conflicts, skipped: skipped,
                                   isFull: request.isFull, events: events)
        log.log("Sync finished: \(result.summary)")
        return result
    }

    // MARK: - File operations

    private nonisolated enum CopyOutcome {
        case copied(Int64)
        case updated(Int64, conflict: Bool)
        case skipped
        case error(String)
    }

    private nonisolated static func apply(_ outcome: CopyOutcome, rel: String, sourceId: Int64?,
                              copied: inout Int, updated: inout Int, skipped: inout Int,
                              conflicts: inout Int, errors: inout Int, bytes: inout Int64,
                              record: (SyncEventType, String, Int64?, String) -> Void) {
        switch outcome {
        case .copied(let size):
            copied += 1; bytes += size
            record(.copied, rel, sourceId, "Copied new file")
        case .updated(let size, let conflict):
            updated += 1; bytes += size
            if conflict {
                conflicts += 1
                record(.conflict, rel, sourceId, "Destination was newer; overwrote (source-of-truth)")
            } else {
                record(.updated, rel, sourceId, "Updated changed file")
            }
        case .skipped:
            skipped += 1
        case .error(let msg):
            errors += 1
            record(.error, rel, sourceId, msg)
        }
    }

    /// Compare-and-copy a single file. Newer/missing/size-differs ⇒ copy.
    private nonisolated static func copyFileIfNeeded(from src: URL, to dst: URL,
                                         srcValues: URLResourceValues?,
                                         fm: FileManager, log: AppLog) -> CopyOutcome {
        let epsilon: TimeInterval = 1  // exFAT has ~2s mtime resolution
        let srcSize = Int64(srcValues?.fileSize ?? 0)
        let srcDate = srcValues?.contentModificationDate ?? .distantPast

        do {
            try fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            return .error("Could not create destination folder: \(error.localizedDescription)")
        }

        let exists = fm.fileExists(atPath: dst.path)
        if !exists {
            do {
                try fm.copyItem(at: src, to: dst)
                setModificationDate(srcDate, on: dst, fm: fm)
                return .copied(srcSize)
            } catch {
                return .error("Copy failed: \(error.localizedDescription)")
            }
        }

        // Destination exists – decide whether to overwrite.
        let dstValues = try? dst.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let dstSize = Int64(dstValues?.fileSize ?? 0)
        let dstDate = dstValues?.contentModificationDate ?? .distantPast

        let sizeDiffers = srcSize != dstSize
        let srcNewer = srcDate.timeIntervalSince(dstDate) > epsilon
        let dstNewer = dstDate.timeIntervalSince(srcDate) > epsilon

        guard sizeDiffers || srcNewer || dstNewer else { return .skipped }

        do {
            try fm.removeItem(at: dst)
            try fm.copyItem(at: src, to: dst)
            setModificationDate(srcDate, on: dst, fm: fm)
            // Overwrote a strictly-newer destination ⇒ record a conflict.
            return .updated(srcSize, conflict: dstNewer && !srcNewer)
        } catch {
            return .error("Update failed: \(error.localizedDescription)")
        }
    }

    /// Set the modification date, ignoring failures (exFAT / FAT have no owners).
    private nonisolated static func setModificationDate(_ date: Date, on url: URL, fm: FileManager) {
        try? fm.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    /// Recreate a symlink at the destination (never follow it).
    private nonisolated static func copySymlink(from src: URL, to dst: URL, fm: FileManager,
                                    record: (SyncEventType, String) -> Void) {
        guard let target = try? fm.destinationOfSymbolicLink(atPath: src.path) else {
            record(.error, "Could not read symlink")
            return
        }
        // If an identical link already exists, leave it.
        if let existing = try? fm.destinationOfSymbolicLink(atPath: dst.path), existing == target {
            return
        }
        do {
            try fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: dst.path) { try? fm.removeItem(at: dst) }
            try fm.createSymbolicLink(atPath: dst.path, withDestinationPath: target)
            record(.copied, "Recreated symlink → \(target)")
        } catch {
            record(.error, "Symlink failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    /// Relative path of `url` within `base` (handles spaces; URL-based).
    private nonisolated static func relativePath(of url: URL, base: URL) -> String {
        let basePath = base.standardizedFileURL.path
        let itemPath = url.standardizedFileURL.path
        if itemPath.hasPrefix(basePath + "/") {
            return String(itemPath.dropFirst(basePath.count + 1))
        }
        return url.lastPathComponent
    }

    /// Does an entry match an enabled exclude rule (global or this source)?
    private nonisolated static func matchesExclude(name: String, relPath: String,
                                       excludes: [ExcludeRule], sourceId: Int64) -> Bool {
        let components = relPath.split(separator: "/").map(String.init)
        for rule in excludes where rule.enabled {
            guard rule.sourceId == nil || rule.sourceId == sourceId else { continue }
            let pattern = rule.pattern.hasSuffix("/") ? String(rule.pattern.dropLast()) : rule.pattern
            if pattern.contains("*") || pattern.contains("?") {
                // Glob: match against the file name or full relative path.
                if globMatch(pattern, name) || globMatch(pattern, relPath) { return true }
            } else {
                // Plain name: match the leaf or any path component.
                if name == pattern || components.contains(pattern) { return true }
            }
        }
        return false
    }

    /// POSIX fnmatch-based glob test.
    private nonisolated static func globMatch(_ pattern: String, _ string: String) -> Bool {
        fnmatch(pattern, string, 0) == 0
    }

    /// Lightweight pre-pass to estimate the number of files for progress.
    private nonisolated static func countFiles(source: ResolvedSource, excludes: [ExcludeRule], fm: FileManager) -> Int {
        guard source.isDirectory else { return 1 }
        guard let enumerator = fm.enumerator(at: source.url,
                                             includingPropertiesForKeys: [.isDirectoryKey],
                                             options: [],
                                             errorHandler: { _, _ in true }) else { return 0 }
        var count = 0
        while let item = enumerator.nextObject() as? URL {
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            let relWithin = relativePath(of: item, base: source.url)
            if matchesExclude(name: item.lastPathComponent, relPath: relWithin,
                              excludes: excludes, sourceId: source.id) {
                if isDir { enumerator.skipDescendants() }
                continue
            }
            if !isDir { count += 1 }
        }
        return count
    }
}
