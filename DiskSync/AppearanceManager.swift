//
//  AppearanceManager.swift
//  ProfessorNotch
//
//  Reads and toggles the system-wide Dark/Light appearance. There is no public
//  API to *set* the system appearance, so we flip it via System Events
//  AppleScript (prompts once for Automation permission). Reading is public
//  (the AppleInterfaceStyle global default).
//

import Foundation
import AppKit

@MainActor
@Observable
final class AppearanceManager {
    static let shared = AppearanceManager()

    private(set) var isDark = false

    private init() { refresh() }

    func refresh() {
        isDark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }

    func toggle() {
        // Flip optimistically so the button reacts instantly, then run the
        // AppleScript that actually changes the system setting.
        isDark.toggle()
        let script = "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode"
        Task.detached(priority: .userInitiated) {
            var error: NSDictionary?
            NSAppleScript(source: script)?.executeAndReturnError(&error)
        }
    }
}
