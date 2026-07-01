//
//  DiskSyncApp.swift
//  DiskSync
//
//  Menu-bar-only (LSUIElement) entry point. The UI lives in:
//   • a notch HUD (NotchController, created by AppDelegate on launch), and
//   • a MenuBarExtra popover + an on-demand Settings window.
//  All surfaces share `AppState.shared`.
//

import SwiftUI
import AppKit

@main
struct DiskSyncApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(AppState.shared)
        } label: {
            Image(systemName: AppState.shared.menuBarSymbol)
                .symbolRenderingMode(.hierarchical)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(AppState.shared)
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
