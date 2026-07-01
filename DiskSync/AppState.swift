//
//  AppState.swift
//  DiskSync
//
//  The MainActor coordinator that ties the engine, monitors, persistence and
//  UI together. SwiftUI observes this object; it owns no heavy work itself —
//  file I/O lives in the SyncManager actor.
//

import Foundation
import SwiftUI
import AppKit

@MainActor
@Observable
final class AppState {
    /// Shared instance used by every surface (menu-bar popover, notch HUD).
    static let shared = AppState()

    // Persisted configuration
    var settings: AppSettings = .default
    var sources: [Source] = []
    var excludes: [ExcludeRule] = []
    var recentRuns: [SyncRun] = []
    var recentEvents: [SyncEvent] = []
    var archivedItems: [ArchivedItem] = []

    // Live UI state
    var status: SyncStatus = .idle
    var progress: SyncProgress?
    var drive: DriveInfo = .disconnected
    var lastSyncDate: Date?
    var bootstrapped = false

    // Engine / monitors
    private var configStore: ConfigStore?
    private let syncManager = SyncManager()
    private var watcher: FolderWatcher?
    private let volumeMonitor = VolumeMonitor()
    private var periodicTimer: Timer?

    private var destinationURL: URL?
    private var lastRunHadErrors = false
    private var lastErrorMessage = ""
    private var isImporting = false
    /// Resolved source URLs, cached so we resolve each bookmark (and start its
    /// security scope) only once per config change — not on every sync.
    private var sourceURLCache: [Int64: URL] = [:]

    // MARK: - Derived UI helpers

    var destinationConfigured: Bool { settings.destinationBookmark != nil || drive.isConnected }

    var canSyncNow: Bool { drive.isConnected && !sources.isEmpty && !isSyncing }

    var isSyncing: Bool { if case .syncing = status { return true } else { return false } }

    var enabledSourceCount: Int { sources.filter(\.enabled).count }

    /// SF Symbol shown in the menu bar, reflecting state.
    var menuBarSymbol: String {
        switch status {
        case .syncing: return "arrow.triangle.2.circlepath"
        case .paused:  return "externaldrive.badge.xmark"
        case .error:   return "exclamationmark.triangle.fill"
        case .idle:    return "externaldrive.fill.badge.checkmark"
        }
    }

    var statusTitle: String {
        switch status {
        case .idle:    return "Synced"
        case .syncing: return "Syncing…"
        case .paused:  return "Paused"
        case .error:   return "Error"
        }
    }

    var statusDetail: String {
        switch status {
        case .idle:
            if let d = lastSyncDate { return "Last sync \(Self.relative(d))" }
            return sources.isEmpty ? "Add folders to begin" : "Up to date"
        case .syncing:
            if let p = progress {
                if p.filesTotalEstimate > 0 {
                    return "\(p.filesProcessed.formatted()) / \(p.filesTotalEstimate.formatted()) files"
                }
                return "Copying \(p.filesProcessed.formatted()) file(s)…"
            }
            return "Working…"
        case .paused:  return "Destination drive disconnected"
        case .error:   return lastErrorMessage.isEmpty ? "Last sync reported errors" : lastErrorMessage
        }
    }

    // MARK: - Bootstrap

    func bootstrap() async {
        guard !bootstrapped else { return }
        bootstrapped = true
        do {
            let store = try ConfigStore()
            configStore = store
            settings = try await store.loadSettings()
            sources = try await store.sources()
            excludes = try await store.excludes()
            recentRuns = try await store.recentRuns()
            recentEvents = try await store.recentEvents()
            archivedItems = try await store.archivedItems()
        } catch {
            AppLog.shared.log("Bootstrap error: \(error)")
        }

        // Reflect the *real* login-item registration state.
        settings.runAtLogin = LoginItem.isEnabled

        await Notifier.requestAuthorization()

        resolveDestination()
        refreshDriveInfo()
        startWatching()
        startMonitors()
        startPeriodicTimer()
        consumeEngineEvents()

        if drive.isConnected && settings.autoSyncEnabled {
            requestSync(full: true)
        } else if !drive.isConnected {
            status = .paused
        }
    }

    private func consumeEngineEvents() {
        let stream = syncManager.events
        Task { [weak self] in
            for await event in stream {
                self?.handle(event)
            }
        }
    }

    private func handle(_ event: SyncManagerEvent) {
        switch event {
        case .started:
            lastRunHadErrors = false
            if drive.isConnected { status = .syncing }
            progress = SyncProgress(filesProcessed: 0, filesTotalEstimate: 0, currentPath: "")
        case .progress(let p):
            progress = p
            if drive.isConnected { status = .syncing }
        case .finished(let result):
            persist(result)
        case .idle:
            progress = nil
            if !drive.isConnected {
                status = .paused
            } else if lastRunHadErrors {
                status = .error(lastErrorMessage)
            } else {
                status = .idle
            }
            refreshDriveInfo()
        }
    }

    private func persist(_ result: SyncRunResult) {
        lastSyncDate = result.finishedAt
        lastRunHadErrors = result.errorsCount > 0
        if lastRunHadErrors { lastErrorMessage = "\(result.errorsCount) error(s) on last sync" }

        Task { [weak self, configStore] in
            try? await configStore?.recordRun(result)
            guard let self else { return }
            if let runs = try? await configStore?.recentRuns() { self.recentRuns = runs }
            if let events = try? await configStore?.recentEvents() { self.recentEvents = events }
            if !result.archived.isEmpty, let items = try? await configStore?.archivedItems() {
                self.archivedItems = items
            }
        }

        let driveName = drive.volumeName.isEmpty ? "the drive" : drive.volumeName
        let title = result.errorsCount > 0 ? "Backup finished with errors" : "Backup complete"
        let body = result.errorsCount > 0
            ? "\(result.summary) → \(driveName)"
            : "Synced \(result.filesCopied) file(s) to \(driveName)"
        let enabled = settings.notificationsEnabled
        // Only notify when something actually happened or an error occurred.
        if result.filesCopied > 0 || result.errorsCount > 0 {
            Task { await Notifier.post(title: title, body: body, enabled: enabled) }
        }
    }

    // MARK: - Destination

    private func resolveDestination() {
        if let data = settings.destinationBookmark, let url = ConfigStore.resolve(data) {
            destinationURL = url
            settings.destinationPath = url.path
        } else {
            destinationURL = URL(fileURLWithPath: settings.destinationPath)
        }
    }

    func refreshDriveInfo() {
        // If the known path is gone, the volume may have remounted elsewhere
        // (e.g. "/Volumes/MetalMini 1"). Re-resolve the bookmark to find it.
        let currentPath = destinationURL?.path ?? ""
        if !FileManager.default.fileExists(atPath: currentPath),
           let data = settings.destinationBookmark,
           let resolved = ConfigStore.resolve(data) {
            destinationURL = resolved
            settings.destinationPath = resolved.path   // in-memory; display + next save
        }

        guard let url = destinationURL else { drive = .disconnected; return }
        let wasConnected = drive.isConnected
        drive = VolumeMonitor.driveInfo(for: url, expectMarker: true)
        if !drive.isConnected && !isSyncing { status = sources.isEmpty ? .idle : .paused }
        // Drive just appeared.
        if drive.isConnected && !wasConnected {
            // Empty app + a drive that remembers its setup ⇒ adopt it.
            if sources.isEmpty { importFromDiskIfPossible(url) }
            writeManifest()
            if settings.autoSyncEnabled { requestSync(full: true) }
        }
    }

    // MARK: - Disk manifest (the drive remembers its setup)

    /// Persist the current config onto the drive so it can be restored later.
    func writeManifest() {
        // Never overwrite the drive's remembered setup with an empty one (e.g.
        // mid-bootstrap or right after removing the last source).
        guard let destinationURL, drive.isConnected, !sources.isEmpty else { return }
        let manifest = DiskManifest(
            updatedAt: Date(),
            deviceName: Host.current().localizedName ?? "Mac",
            sources: sources.map { .init(path: $0.path, isDirectory: $0.isDirectory, enabled: $0.enabled) },
            excludes: excludes.map(\.pattern),
            mirrorEnabled: settings.mirrorEnabled
        )
        let root = destinationURL
        Task.detached { manifest.write(toDestination: root) }
    }

    /// Adopt the drive's remembered folders when this app has none configured.
    private func importFromDiskIfPossible(_ root: URL) {
        guard !isImporting, sources.isEmpty,
              let manifest = DiskManifest.read(fromDestination: root),
              !manifest.sources.isEmpty, let store = configStore else { return }
        isImporting = true   // set synchronously to block a concurrent second import
        settings.mirrorEnabled = manifest.mirrorEnabled
        saveSettings()
        Task { [weak self] in
            var added: [Source] = []
            for s in manifest.sources where FileManager.default.fileExists(atPath: s.path) {
                if let src = try? await store.addSource(url: URL(fileURLWithPath: s.path)) { added.append(src) }
            }
            guard let self else { return }
            self.sources.append(contentsOf: added)
            self.isImporting = false
            self.restartWatching()
            if self.drive.isConnected { self.requestSync(full: true) }
        }
    }

    /// Let the user pick / confirm the destination, then write the marker.
    func pickDestination() {
        let panel = NSOpenPanel()
        panel.title = "Choose the backup destination"
        panel.message = "Select a folder on your external drive. ProfessorNotch will write a small marker file there."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if let url = destinationURL, FileManager.default.fileExists(atPath: url.path) {
            panel.directoryURL = url
        }
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            // Seed the marker as a config manifest so the drive remembers its setup.
            let manifest = DiskManifest(
                updatedAt: Date(),
                deviceName: Host.current().localizedName ?? "Mac",
                sources: sources.map { .init(path: $0.path, isDirectory: $0.isDirectory, enabled: $0.enabled) },
                excludes: excludes.map(\.pattern),
                mirrorEnabled: settings.mirrorEnabled
            )
            manifest.write(toDestination: url)
        } catch {
            AppLog.shared.log("Failed to write marker at \(url.path): \(error)")
            presentError("Couldn't prepare the destination: \(error.localizedDescription)")
            return
        }

        destinationURL = url
        settings.destinationPath = url.path
        settings.destinationBookmark = ConfigStore.makeBookmark(for: url)
        saveSettings()
        refreshDriveInfo()
        if drive.isConnected { requestSync(full: true) }
    }

    // MARK: - Source management

    func addSourcesViaPanel() {
        let panel = NSOpenPanel()
        panel.title = "Add folders or files to sync"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        NSApp.activate(ignoringOtherApps: true)   // agent app: bring the panel to front
        guard panel.runModal() == .OK else { return }
        addSources(urls: panel.urls)
    }

    func addSuggested(_ item: SuggestedItem) {
        addSources(urls: [item.url])
    }

    func addSources(urls: [URL]) {
        let existing = Set(sources.map(\.path))
        let fresh = urls.filter { !existing.contains($0.path) }
        guard !fresh.isEmpty, let store = configStore else { return }
        Task { [weak self] in
            var added: [Source] = []
            for url in fresh {
                if let s = try? await store.addSource(url: url) { added.append(s) }
            }
            guard let self else { return }
            self.sources.append(contentsOf: added)
            self.restartWatching()
            if self.drive.isConnected { self.requestSync(full: true) }
        }
    }

    func toggleSource(_ source: Source, enabled: Bool) {
        guard let idx = sources.firstIndex(where: { $0.id == source.id }) else { return }
        sources[idx].enabled = enabled
        let id = source.id
        Task { [configStore] in try? await configStore?.setSourceEnabled(id, enabled) }
        restartWatching()
        if enabled && drive.isConnected { requestSync(full: false, sourceIDs: [id]) }
    }

    func removeSource(_ source: Source) {
        sources.removeAll { $0.id == source.id }
        let id = source.id
        Task { [configStore] in try? await configStore?.removeSource(id) }
        restartWatching()
    }

    // MARK: - Exclude management

    func addExclude(pattern: String, sourceId: Int64? = nil) {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let store = configStore else { return }
        Task { [weak self] in
            if let rule = try? await store.addExclude(pattern: trimmed, sourceId: sourceId) {
                self?.excludes.append(rule)
            }
        }
    }

    func updateExclude(_ rule: ExcludeRule) {
        guard let idx = excludes.firstIndex(where: { $0.id == rule.id }) else { return }
        excludes[idx] = rule
        Task { [configStore] in try? await configStore?.updateExclude(rule) }
    }

    func removeExclude(_ rule: ExcludeRule) {
        excludes.removeAll { $0.id == rule.id }
        let id = rule.id
        Task { [configStore] in try? await configStore?.removeExclude(id) }
    }

    // MARK: - Settings mutations

    func saveSettings() {
        let snapshot = settings
        Task { [configStore] in try? await configStore?.saveSettings(snapshot) }
        writeManifest()
    }

    func setAutoSync(_ on: Bool) {
        settings.autoSyncEnabled = on
        saveSettings()
        if on && drive.isConnected { requestSync(full: true) }
    }

    func setNotifications(_ on: Bool) {
        settings.notificationsEnabled = on
        saveSettings()
    }

    func setMirror(_ on: Bool) {
        settings.mirrorEnabled = on
        saveSettings()
        // A fresh full reconcile applies the new policy (archives orphans).
        if on && drive.isConnected { requestSync(full: true) }
    }

    // MARK: - Archive (recovery)

    /// Restore an archived item back to its original location on the Mac.
    func restoreArchived(_ item: ArchivedItem) {
        guard let destinationURL else { return }
        let archiveSource = destinationURL
            .appendingPathComponent(Defaults.archiveFolderName)
            .appendingPathComponent(item.archivePath)
        let restoreTarget = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(item.relativePath)
        let fm = FileManager.default
        guard fm.fileExists(atPath: archiveSource.path) else {
            presentError("The archived file is not on the connected drive.")
            return
        }
        // Copy to a temp first, then atomically swap in — never delete the live
        // file at the restore target until the copy is confirmed.
        let tmp = restoreTarget.deletingLastPathComponent()
            .appendingPathComponent(".disksync-restore-\(UUID().uuidString)")
        do {
            try fm.createDirectory(at: restoreTarget.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: archiveSource, to: tmp)
            if fm.fileExists(atPath: restoreTarget.path) {
                _ = try fm.replaceItemAt(restoreTarget, withItemAt: tmp)
            } else {
                try fm.moveItem(at: tmp, to: restoreTarget)
            }
            try? fm.removeItem(at: archiveSource)          // moved back out of the archive
        } catch {
            try? fm.removeItem(at: tmp)
            presentError("Restore failed: \(error.localizedDescription)")
            return
        }
        forgetArchived(item)
    }

    /// Permanently remove an archived item from the drive.
    func deleteArchivedPermanently(_ item: ArchivedItem) {
        if let destinationURL {
            let archiveSource = destinationURL
                .appendingPathComponent(Defaults.archiveFolderName)
                .appendingPathComponent(item.archivePath)
            try? FileManager.default.removeItem(at: archiveSource)
        }
        forgetArchived(item)
    }

    private func forgetArchived(_ item: ArchivedItem) {
        archivedItems.removeAll { $0.id == item.id }
        let id = item.id
        Task { [configStore] in try? await configStore?.removeArchived(id) }
    }

    func setSyncInterval(_ minutes: Int) {
        settings.syncIntervalMinutes = max(1, minutes)
        saveSettings()
        startPeriodicTimer()
    }

    func setRunAtLogin(_ on: Bool) {
        do {
            try LoginItem.setEnabled(on)
        } catch {
            AppLog.shared.log("Login item toggle failed: \(error)")
            presentError("Couldn't update Open at Login: \(error.localizedDescription)")
        }
        settings.runAtLogin = LoginItem.isEnabled
        saveSettings()
    }

    // MARK: - Actions

    func syncNow() { requestSync(full: true) }

    func openLog() {
        let url = AppLog.shared.fileURL
        if !FileManager.default.fileExists(atPath: url.path) {
            try? Data().write(to: url)
        }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Sync requests

    /// Resolves a source to a URL once and caches it (starting its security
    /// scope a single time), avoiding a resolve+startAccessing on every sync.
    private func resolvedURL(for source: Source) -> URL {
        if let cached = sourceURLCache[source.id] { return cached }
        let url = source.bookmark.flatMap { ConfigStore.resolve($0) } ?? source.url
        sourceURLCache[source.id] = url
        return url
    }

    private func requestSync(full: Bool, sourceIDs: Set<Int64>? = nil, changedPaths: [String]? = nil) {
        guard let destinationURL else { return }
        // Refuse to write unless the marker confirms the target.
        let markerURL = destinationURL.appendingPathComponent(Defaults.markerFileName)
        guard FileManager.default.fileExists(atPath: markerURL.path) else {
            status = sources.isEmpty ? .idle : .paused
            return
        }

        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        let candidates = sources.filter { source in
            guard source.enabled else { return false }
            if let ids = sourceIDs { return ids.contains(source.id) }
            return true
        }

        let resolved: [ResolvedSource] = candidates.compactMap { source in
            let url = resolvedURL(for: source)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let rel: String
            let p = url.standardizedFileURL.path
            if p.hasPrefix(home + "/") {
                rel = String(p.dropFirst(home.count + 1))
            } else {
                rel = url.lastPathComponent
            }
            return ResolvedSource(id: source.id, url: url, isDirectory: source.isDirectory, homeRelativePath: rel)
        }

        guard !resolved.isEmpty else { return }
        let request = SyncRequest(sources: resolved, destinationRoot: destinationURL,
                                  excludes: excludes, isFull: full,
                                  changedPaths: full ? nil : changedPaths,
                                  mirrorEnabled: settings.mirrorEnabled)
        Task { [syncManager] in await syncManager.enqueue(request) }
    }

    // MARK: - Watching & monitoring

    private func startWatching() { restartWatching() }

    private func restartWatching() {
        sourceURLCache.removeAll()   // sources changed → re-resolve lazily next sync
        writeManifest()              // sources changed → update the drive's memory
        watcher?.stop()
        // Watch directory sources directly; for single-file sources watch their
        // parent folder (FSEvents is unreliable when pointed at a lone file).
        var watchPaths = Set<String>()
        for source in sources where source.enabled {
            if source.isDirectory {
                watchPaths.insert(source.path)
            } else {
                watchPaths.insert((source.path as NSString).deletingLastPathComponent)
            }
        }
        let paths = Array(watchPaths)
        guard !paths.isEmpty else { watcher = nil; return }
        let watcher = FolderWatcher(paths: paths) { [weak self] changed in
            Task { @MainActor [weak self] in self?.handleFileChanges(changed) }
        }
        watcher.start()
        self.watcher = watcher
    }

    private func handleFileChanges(_ changedPaths: Set<String>) {
        guard settings.autoSyncEnabled, drive.isConnected else { return }
        // Keep only paths that live under an enabled source, and sync *just those*
        // paths — never re-walk the whole tree on every file event.
        let relevant = changedPaths.filter { path in
            sources.contains { $0.enabled && (path == $0.path || path.hasPrefix($0.path + "/")) }
        }
        guard !relevant.isEmpty else { return }
        requestSync(full: false, changedPaths: Array(relevant))
    }

    private func startMonitors() {
        volumeMonitor.onVolumeChange = { [weak self] in self?.refreshDriveInfo() }
        volumeMonitor.onWake = { [weak self] in
            guard let self, self.settings.autoSyncEnabled else { return }
            self.refreshDriveInfo()
            if self.drive.isConnected { self.requestSync(full: true) }
        }
        volumeMonitor.start()
    }

    private func startPeriodicTimer() {
        periodicTimer?.invalidate()
        let interval = TimeInterval(max(1, settings.syncIntervalMinutes) * 60)
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.settings.autoSyncEnabled, self.drive.isConnected else { return }
                self.requestSync(full: true)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        periodicTimer = timer
    }

    // MARK: - Errors

    private func presentError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "ProfessorNotch"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }

    // MARK: - Formatting

    static func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }
}
