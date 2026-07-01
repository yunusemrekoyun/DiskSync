//
//  LauncherStore.swift
//  DiskSync
//
//  Backs the Apps tab: user-pinned shortcuts, plus two auto rows —
//  "Frequent" (frecency: launch count weighted by how recently used) and
//  "Recent" (by last-used time). Usage is tracked locally via NSWorkspace and
//  persisted in UserDefaults. Fully local.
//

import Foundation
import AppKit
import UniformTypeIdentifiers

nonisolated struct LauncherApp: Identifiable, Hashable, Codable, Sendable {
    var path: String
    var name: String
    var id: String { path }
}

/// Per-app usage record used to compute the Frequent / Recent rows.
nonisolated struct AppUsage: Codable, Sendable {
    var path: String
    var name: String
    var count: Int
    var lastUsed: Date
}

@MainActor
@Observable
final class LauncherStore {
    /// Shared, long-lived store — the Apps view is created/destroyed as the
    /// notch opens, so a per-view instance would leak an NSWorkspace observer
    /// (and duplicate launch counts) on every open.
    static let shared = LauncherStore()

    var pinned: [LauncherApp] = []
    private var usage: [String: AppUsage] = [:]

    private let pinnedKey = "launcher.pinned"
    private let usageKey = "launcher.usage"
    private let maxTracked = 60
    private var iconCache: [String: NSImage] = [:]

    private init() {
        load()
        seedUsageIfNeeded()
        observeLaunches()
    }

    /// Cached app icon (avoids hitting LaunchServices on every SwiftUI render).
    func icon(for path: String) -> NSImage {
        if let cached = iconCache[path] { return cached }
        let image = NSWorkspace.shared.icon(forFile: path)
        iconCache[path] = image
        return image
    }

    // MARK: - Derived rows

    private var pinnedPaths: Set<String> { Set(pinned.map(\.path)) }

    /// Recently opened apps (most recent first), excluding pinned ones.
    var recentSuggestions: [LauncherApp] {
        usage.values
            .sorted { $0.lastUsed > $1.lastUsed }
            .filter { !pinnedPaths.contains($0.path) }
            .map { LauncherApp(path: $0.path, name: $0.name) }
    }

    /// Frequently used apps, weighted toward recent usage (frecency).
    var frequentSuggestions: [LauncherApp] {
        let now = Date()   // sample the clock once, not per comparison
        return usage.values
            .sorted { Self.frecency($0, now: now) > Self.frecency($1, now: now) }
            .filter { !pinnedPaths.contains($0.path) }
            .map { LauncherApp(path: $0.path, name: $0.name) }
    }

    /// count × recency multiplier — recent days count for much more.
    private static func frecency(_ u: AppUsage, now: Date) -> Double {
        let ageDays = max(0, now.timeIntervalSince(u.lastUsed) / 86_400)
        let boost: Double
        switch ageDays {
        case ..<1:  boost = 4
        case ..<3:  boost = 2
        case ..<7:  boost = 1
        case ..<30: boost = 0.5
        default:    boost = 0.25
        }
        return Double(u.count) * boost
    }

    // MARK: - Launch

    func launch(_ app: LauncherApp) {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: app.path),
                                           configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: - Pins

    func addPinnedViaPanel() {
        let panel = NSOpenPanel()
        panel.title = "Add a shortcut"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        NSApp.activate(ignoringOtherApps: true)   // agent app: bring the panel to front
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { addPinned(url) }
    }

    func addPinned(_ url: URL) {
        guard !pinned.contains(where: { $0.path == url.path }) else { return }
        pinned.append(LauncherApp(path: url.path, name: Self.displayName(url)))
        save()
    }

    func removePinned(_ app: LauncherApp) {
        pinned.removeAll { $0.id == app.id }
        save()
    }

    // MARK: - Usage tracking

    private func observeLaunches() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let running = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  running.activationPolicy == .regular,
                  let url = running.bundleURL,
                  let name = running.localizedName,
                  url.path != Bundle.main.bundlePath else { return }
            let path = url.path
            Task { @MainActor in self?.record(path: path, name: name) }
        }
    }

    private func record(path: String, name: String) {
        var entry = usage[path] ?? AppUsage(path: path, name: name, count: 0, lastUsed: Date())
        entry.count += 1
        entry.lastUsed = Date()
        entry.name = name
        usage[path] = entry
        pruneUsageIfNeeded()
        save()
    }

    private func pruneUsageIfNeeded() {
        guard usage.count > maxTracked else { return }
        // Drop the least-recently-used entries beyond the cap.
        let keep = usage.values.sorted { $0.lastUsed > $1.lastUsed }.prefix(maxTracked)
        usage = Dictionary(uniqueKeysWithValues: keep.map { ($0.path, $0) })
    }

    private func seedUsageIfNeeded() {
        guard usage.isEmpty else { return }
        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular {
            guard let url = app.bundleURL, let name = app.localizedName,
                  url.path != Bundle.main.bundlePath else { continue }
            usage[url.path] = AppUsage(path: url.path, name: name, count: 1, lastUsed: Date())
        }
    }

    // MARK: - Persistence

    private func load() {
        let decoder = JSONDecoder()
        if let data = UserDefaults.standard.data(forKey: pinnedKey),
           let list = try? decoder.decode([LauncherApp].self, from: data) {
            pinned = list.filter { FileManager.default.fileExists(atPath: $0.path) }
        }
        if let data = UserDefaults.standard.data(forKey: usageKey),
           let map = try? decoder.decode([String: AppUsage].self, from: data) {
            usage = map.filter { FileManager.default.fileExists(atPath: $0.key) }
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(pinned) { UserDefaults.standard.set(data, forKey: pinnedKey) }
        if let data = try? encoder.encode(usage) { UserDefaults.standard.set(data, forKey: usageKey) }
    }

    private static func displayName(_ url: URL) -> String {
        let name = FileManager.default.displayName(atPath: url.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }
}
