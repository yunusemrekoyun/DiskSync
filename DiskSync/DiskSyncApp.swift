//
//  DiskSyncApp.swift
//  DiskSync
//
//  Menu-bar-only (LSUIElement) entry point. The UI lives in a MenuBarExtra
//  popover plus an on-demand Settings window. A single AppState instance is
//  shared across both scenes.
//

import SwiftUI

@main
struct DiskSyncApp: App {
    @State private var app = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(app)
        } label: {
            Image(systemName: app.menuBarSymbol)
                .symbolRenderingMode(.hierarchical)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(app)
        }
    }
}
