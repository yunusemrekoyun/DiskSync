//
//  Preferences.swift
//  DiskSync (ProfessorNotch)
//
//  App-wide preferences for the notch hub (which tabs show, haptics, clipboard
//  history, artwork networking). Backed by UserDefaults; observed by the views
//  and managers that consume them. The DiskSync backup settings remain in
//  SQLite (see AppSettings) — this is only the hub's own preferences.
//

import Foundation

@MainActor
@Observable
final class Preferences {
    static let shared = Preferences()
    private let store = UserDefaults.standard

    // Notch module visibility (Sync is core and always shown).
    var showNowPlaying: Bool { didSet { store.set(showNowPlaying, forKey: "pref.nowPlaying") } }
    var showBattery: Bool    { didSet { store.set(showBattery, forKey: "pref.battery") } }
    var showLauncher: Bool   { didSet { store.set(showLauncher, forKey: "pref.launcher") } }
    var showShelf: Bool      { didSet { store.set(showShelf, forKey: "pref.shelf") } }
    var showSystem: Bool     { didSet { store.set(showSystem, forKey: "pref.system") } }

    var hapticsEnabled: Bool { didSet { store.set(hapticsEnabled, forKey: "pref.haptics") } }

    /// When true, hovering the notch reopens the tab you last used; when false
    /// it always opens the first (Control) tab.
    var openLastTab: Bool { didSet { store.set(openLastTab, forKey: "pref.openLastTab") } }

    var clipboardEnabled: Bool {
        didSet {
            store.set(clipboardEnabled, forKey: "pref.clipboard")
            ClipboardManager.shared.setEnabled(clipboardEnabled)
        }
    }

    /// Allow downloading album art over the network (Spotify). Off ⇒ fully offline.
    var artworkNetworkEnabled: Bool { didSet { store.set(artworkNetworkEnabled, forKey: "pref.artworkNetwork") } }

    private init() {
        // didSet does not fire for assignments in init, so no write-back here.
        // Use a local reference (not self.store) since self isn't ready yet.
        let d = UserDefaults.standard
        func flag(_ key: String, default def: Bool = true) -> Bool {
            d.object(forKey: key) == nil ? def : d.bool(forKey: key)
        }
        showNowPlaying = flag("pref.nowPlaying")
        showBattery = flag("pref.battery")
        showLauncher = flag("pref.launcher")
        showShelf = flag("pref.shelf")
        showSystem = flag("pref.system")
        hapticsEnabled = flag("pref.haptics")
        openLastTab = flag("pref.openLastTab", default: false)
        clipboardEnabled = flag("pref.clipboard")
        // Off by default so a stock install is fully offline until the user
        // explicitly opts in (honors the "100% local & offline" promise).
        artworkNetworkEnabled = flag("pref.artworkNetwork", default: false)
    }
}
