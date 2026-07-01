//
//  LauncherStore.swift
//  DiskSync
//
//  Backs the Apps tab: a row of user-pinned shortcuts plus a row of recently
//  launched apps (tracked locally via NSWorkspace). Fully local; pins persist
//  in UserDefaults.
//

import Foundation
import AppKit
import UniformTypeIdentifiers

nonisolated struct LauncherApp: Identifiable, Hashable, Codable, Sendable {
    var path: String
    var name: String
    var id: String { path }
}

@MainActor
@Observable
final class LauncherStore {
    var pinned: [LauncherApp] = []
    var recents: [LauncherApp] = []

    private let pinnedKey = "launcher.pinned"
    private let recentsKey = "launcher.recents"
    private let maxRecents = 12

    init() {
        load()
        seedRecentsIfNeeded()
        observeLaunches()
    }

    // MARK: - Launch

    func launch(_ app: LauncherApp) {
        let url = URL(fileURLWithPath: app.path)
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
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

    /// Recent apps not already pinned (suggestions).
    var recentSuggestions: [LauncherApp] {
        let pinnedPaths = Set(pinned.map(\.path))
        return recents.filter { !pinnedPaths.contains($0.path) }
    }

    // MARK: - Recents tracking

    private func observeLaunches() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            // Extract Sendable values here, then hop to the MainActor with them.
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
        let app = LauncherApp(path: path, name: name)
        recents.removeAll { $0.id == app.id }
        recents.insert(app, at: 0)
        if recents.count > maxRecents { recents = Array(recents.prefix(maxRecents)) }
        save()
    }

    private func seedRecentsIfNeeded() {
        guard recents.isEmpty else { return }
        recents = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleURL != nil && $0.bundleURL?.path != Bundle.main.bundlePath }
            .compactMap { app in
                guard let url = app.bundleURL, let name = app.localizedName else { return nil }
                return LauncherApp(path: url.path, name: name)
            }
        recents = Array(recents.prefix(maxRecents))
    }

    // MARK: - Persistence

    private func load() {
        let decoder = JSONDecoder()
        if let data = UserDefaults.standard.data(forKey: pinnedKey),
           let list = try? decoder.decode([LauncherApp].self, from: data) {
            pinned = list.filter { FileManager.default.fileExists(atPath: $0.path) }
        }
        if let data = UserDefaults.standard.data(forKey: recentsKey),
           let list = try? decoder.decode([LauncherApp].self, from: data) {
            recents = list.filter { FileManager.default.fileExists(atPath: $0.path) }
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(pinned) { UserDefaults.standard.set(data, forKey: pinnedKey) }
        if let data = try? encoder.encode(recents) { UserDefaults.standard.set(data, forKey: recentsKey) }
    }

    private static func displayName(_ url: URL) -> String {
        let name = FileManager.default.displayName(atPath: url.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }
}
