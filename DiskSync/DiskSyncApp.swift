//
//  DiskSyncApp.swift
//  DiskSync
//
//  Notch-only entry point. There is no menu-bar icon and no Dock icon
//  (LSUIElement) — the entire UI lives in the notch HUD created by AppDelegate.
//  Settings and Quit are reachable from the notch's Sync tab. A Settings scene
//  is kept so the on-demand preferences window works.
//

import SwiftUI
import AppKit

@main
struct DiskSyncApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var app = AppState.shared

    var body: some Scene {
        Settings {
            SettingsView()
                .environment(app)
        }
    }
}

/// Owns app lifecycle: boots the engine and installs the notch HUD.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notch: NotchController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let app = AppState.shared
        Task { await app.bootstrap() }

        let notch = NotchController(app: app)
        notch.install()
        self.notch = notch
    }
}

