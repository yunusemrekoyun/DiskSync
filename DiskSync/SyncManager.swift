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
///
/// `changedPaths` (set only for FSEvents-driven incremental runs) restricts the
/// work to the exact paths that changed, instead of re-walking the whole tree.
/// A `nil` `changedPaths` (or `isFull == true`) means a full reconcile.
nonisolated struct SyncRequest: Sendable {
    var sources: [ResolvedSource]
    var destinationRoot: URL
    var excludes: [ExcludeRule]
    var isFull: Bool
    var changedPaths: [String]?
    /// Mirror mode: relocate destination items whose source no longer exists
    /// into the on-drive archive (recoverable), instead of leaving them.
    var mirrorEnabled: Bool
}

/// A file mirror mode moved into the archive (returned by the engine, then
/// persisted so the recovery UI can list and restore it).
nonisolated struct ArchivedRecord: Sendable {
    var relativePath: String
    var archivePath: String
    var deletedAt: Date
    var bytes: Int64
    var sourceId: Int64?
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
    var archived: [ArchivedRecord]

    var summary: String {
        var parts = ["\(filesCopied) file(s)", ByteCountFormatter.string(fromByteCount: bytesCopied, countStyle: .file)]
        if !archived.isEmpty { parts.append("\(archived.count) archived") }
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

    /// Merge two requests: union sources by id, "full" wins, latest dest/excludes,
    /// and accumulate changed paths (dropped entirely once any request is full).
    private nonisolated static func merge(_ existing: SyncRequest?, _ new: SyncRequest) -> SyncRequest {
        guard let existing else { return new }
        var byID: [Int64: ResolvedSource] = [:]
        for s in existing.sources { byID[s.id] = s }
        for s in new.sources { byID[s.id] = s }
        let isFull = existing.isFull || new.isFull
        let changed: [String]? = isFull ? nil : ((existing.changedPaths ?? []) + (new.changedPaths ?? []))
        return SyncRequest(sources: Array(byID.values),
                           destinationRoot: new.destinationRoot,
                           excludes: new.excludes,
                           isFull: isFull,
                           changedPaths: changed,
                           mirrorEnabled: existing.mirrorEnabled || new.mirrorEnabled)
    }

    // MARK: - Core algorithm (nonisolated: pure file work, no actor state)

    private nonisolated static func performSync(_ request: SyncRequest,
                                    progress: @Sendable (SyncProgress) -> Void) -> SyncRunResult {
        let started = Date()
        let fm = FileManager.default
        let log = AppLog.shared
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]

        var copied = 0, updated = 0, skipped = 0, conflicts = 0, errors = 0
        var bytes: Int64 = 0
        var events: [PendingEvent] = []
        var archived: [ArchivedRecord] = []
        var processed = 0

        let destRootPath = request.destinationRoot.standardizedFileURL.path
        let archiveRoot = request.destinationRoot.appendingPathComponent(Defaults.archiveFolderName)

        func record(_ type: SyncEventType, _ rel: String, _ sourceId: Int64?, _ message: String) {
            events.append(PendingEvent(timestamp: Date(), type: type, relativePath: rel, sourceId: sourceId, message: message))
        }

        /// A destination path's location relative to the destination root
        /// (== the home-relative path, since the drive mirrors `~`).
        func relToDestRoot(_ url: URL) -> String {
            let p = url.standardizedFileURL.path
            return p.hasPrefix(destRootPath + "/") ? String(p.dropFirst(destRootPath.count + 1)) : url.lastPathComponent
        }

        /// Move one destination file into the archive (mirror mode). Never a
        /// hard delete; the recovery UI can restore it later.
        func archiveFile(_ destFile: URL, sourceId: Int64?) {
            // Never archive things already inside the archive folder.
            if destFile.path.hasPrefix(archiveRoot.standardizedFileURL.path) { return }
            let relHome = relToDestRoot(destFile)
            var target = archiveRoot.appendingPathComponent(relHome)
            if fm.fileExists(atPath: target.path) {
                let stamp = Int(Date().timeIntervalSince1970)
                target = target.deletingLastPathComponent()
                    .appendingPathComponent(target.lastPathComponent + ".\(stamp)")
            }
            let size = ((try? destFile.resourceValues(forKeys: [.fileSizeKey]))?.fileSize).map(Int64.init) ?? 0
            do {
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.moveItem(at: destFile, to: target)
                let archiveRel = relToDestRoot(target)
                archived.append(ArchivedRecord(relativePath: relHome, archivePath: archiveRel,
                                               deletedAt: Date(), bytes: size, sourceId: sourceId))
            } catch {
                errors += 1
                record(.error, relHome, sourceId, "Archive failed: \(error.localizedDescription)")
            }
        }

        /// Archive a destination file, or all files under a destination folder.
        func archiveDestination(_ destURL: URL, sourceId: Int64?) {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: destURL.path, isDirectory: &isDir) else { return }
            if isDir.boolValue {
                guard let en = fm.enumerator(at: destURL, includingPropertiesForKeys: [.isDirectoryKey],
                                             options: [], errorHandler: { _, _ in true }) else { return }
                var files: [URL] = []
                while let f = en.nextObject() as? URL {
                    if (try? f.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory != true { files.append(f) }
                }
                for f in files { archiveFile(f, sourceId: sourceId) }
            } else {
                archiveFile(destURL, sourceId: sourceId)
            }
        }

        /// Mirror reverse-scan: archive destination files whose source is gone.
        func reverseScan(_ source: ResolvedSource) {
            let destBase = request.destinationRoot.appendingPathComponent(source.homeRelativePath)
            guard fm.fileExists(atPath: destBase.path) else { return }
            guard let enumerator = fm.enumerator(at: destBase,
                                                 includingPropertiesForKeys: [.isDirectoryKey],
                                                 options: [], errorHandler: { _, _ in true }) else { return }
            var orphans: [URL] = []
            while let item = enumerator.nextObject() as? URL {
                if (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true { continue }
                let relWithin = relativePath(of: item, base: destBase)
                if matchesExclude(name: item.lastPathComponent, relPath: relWithin,
                                  excludes: request.excludes, sourceId: source.id) { continue }
                let sourceItem = source.url.appendingPathComponent(relWithin)
                if !fm.fileExists(atPath: sourceItem.path) { orphans.append(item) }
            }
            // Archive after enumeration so we don't mutate the tree mid-walk.
            for orphan in orphans { archiveFile(orphan, sourceId: source.id) }
        }

        // Copy a single entry (file / symlink / directory marker).
        func copyOne(_ url: URL, _ rv: URLResourceValues?, _ source: ResolvedSource) {
            let isDir = rv?.isDirectory ?? false
            let isLink = rv?.isSymbolicLink ?? false
            let relWithin = relativePath(of: url, base: source.url)
            let relHome = relWithin.isEmpty ? source.homeRelativePath : source.homeRelativePath + "/" + relWithin
            let dest = request.destinationRoot.appendingPathComponent(relHome)

            if isLink {
                copySymlink(from: url, to: dest, fm: fm) { type, msg in
                    if type == .error { errors += 1 } else if type == .copied { copied += 1 }
                    record(type, relHome, source.id, msg)
                }
            } else if isDir {
                try? fm.createDirectory(at: dest, withIntermediateDirectories: true)
            } else {
                switch copyFileIfNeeded(from: url, to: dest, srcValues: rv, fm: fm, log: log) {
                case .copied(let size):
                    copied += 1; bytes += size
                    record(.copied, relHome, source.id, "Copied new file")
                case .updated(let size, let conflict):
                    updated += 1; bytes += size
                    if conflict {
                        conflicts += 1
                        record(.conflict, relHome, source.id, "Destination was newer; overwrote (source-of-truth)")
                    } else {
                        record(.updated, relHome, source.id, "Updated changed file")
                    }
                case .skipped:
                    skipped += 1
                case .error(let msg):
                    errors += 1
                    record(.error, relHome, source.id, msg)
                }
            }
            processed += 1
            if processed % 50 == 0 {
                progress(SyncProgress(filesProcessed: processed, filesTotalEstimate: 0, currentPath: relHome))
            }
        }

        // Enumerate a directory tree once and copy everything (respecting excludes).
        func syncTree(_ root: URL, _ source: ResolvedSource) {
            guard let enumerator = fm.enumerator(at: root,
                                                 includingPropertiesForKeys: Array(keys),
                                                 options: [],
                                                 errorHandler: { url, error in
                                                     log.log("Enumerate error at \(url.path): \(error.localizedDescription)")
                                                     return true
                                                 }) else { return }
            while let item = enumerator.nextObject() as? URL {
                let rv = try? item.resourceValues(forKeys: keys)
                let relWithin = relativePath(of: item, base: source.url)
                if matchesExclude(name: item.lastPathComponent, relPath: relWithin,
                                  excludes: request.excludes, sourceId: source.id) {
                    if rv?.isDirectory == true { enumerator.skipDescendants() }
                    skipped += 1
                    continue
                }
                copyOne(item, rv, source)
            }
        }

        let isFull = request.isFull || request.changedPaths == nil
        log.log("Sync started (\(isFull ? "full reconcile" : "incremental"), \(request.sources.count) source(s))")
        progress(SyncProgress(filesProcessed: 0, filesTotalEstimate: 0, currentPath: ""))

        if isFull {
            // Full reconcile: walk every enabled source.
            for source in request.sources {
                if source.isDirectory {
                    syncTree(source.url, source)
                } else {
                    let rv = try? source.url.resourceValues(forKeys: keys)
                    copyOne(source.url, rv, source)
                }
            }
            // Mirror mode: archive destination files whose source no longer exists.
            if request.mirrorEnabled {
                for source in request.sources where source.isDirectory { reverseScan(source) }
            }
        } else {
            // Targeted: only the exact paths FSEvents reported — no full walk.
            var seen = Set<String>()
            for path in request.changedPaths ?? [] where seen.insert(path).inserted {
                guard let source = request.sources.first(where: {
                    path == $0.url.path || path.hasPrefix($0.url.path + "/")
                }) else { continue }
                let url = URL(fileURLWithPath: path)
                let relWithin = relativePath(of: url, base: source.url)
                if matchesExclude(name: url.lastPathComponent, relPath: relWithin,
                                  excludes: request.excludes, sourceId: source.id) { continue }

                if let rv = try? url.resourceValues(forKeys: keys) {
                    if rv.isDirectory == true {
                        syncTree(url, source)
                    } else {
                        copyOne(url, rv, source)
                    }
                } else {
                    // Source path is gone. Additive mode leaves the drive copy;
                    // mirror mode relocates it to the archive.
                    if request.mirrorEnabled {
                        let relHome = relWithin.isEmpty ? source.homeRelativePath
                                                        : source.homeRelativePath + "/" + relWithin
                        archiveDestination(request.destinationRoot.appendingPathComponent(relHome),
                                           sourceId: source.id)
                    }
                }
            }
        }

        progress(SyncProgress(filesProcessed: processed, filesTotalEstimate: 0, currentPath: ""))

        let status = errors > 0 ? "completed_with_errors" : "completed"
        let result = SyncRunResult(startedAt: started, finishedAt: Date(), status: status,
                                   filesCopied: copied + updated, bytesCopied: bytes,
                                   errorsCount: errors, conflicts: conflicts, skipped: skipped,
                                   isFull: request.isFull, events: events, archived: archived)
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
}
