//
//  Haptics.swift
//  ProfessorNotch
//
//  Tiered trackpad haptics. Each feedback call declares the minimum level at
//  which it fires; the user picks the level in Settings. No-op on devices
//  without a Force Touch trackpad; respects system settings.
//
//  Levels:  Off → nothing · Minimal → notch open only · Medium → + tabs & events
//           · High → + button taps · Max → + hovering controls
//

import AppKit
import SwiftUI

nonisolated enum HapticLevel: Int, CaseIterable, Identifiable, Sendable {
    case off = 0, minimal, medium, high, max
    var id: Int { rawValue }

    var label: String {
        switch self {
        case .off:     return "Off"
        case .minimal: return "Minimal"
        case .medium:  return "Medium"
        case .high:    return "High"
        case .max:     return "Max"
        }
    }

    var detail: String {
        switch self {
        case .off:     return "No haptic feedback."
        case .minimal: return "Only when the notch opens."
        case .medium:  return "Notch, tab changes, and events."
        case .high:    return "Also every button tap."
        case .max:     return "Also when hovering controls."
        }
    }
}

@MainActor
enum Haptics {
    /// Subtle tick when the notch opens (Minimal+).
    static func notchOpen() { fire(.alignment, .minimal) }
    /// Switching tabs (Medium+).
    static func tab()       { fire(.generic, .medium) }
    /// Moving the cursor across tabs (Medium+).
    static func tabHover()  { fire(.alignment, .medium) }
    /// System-ish events: file drop, charger (un)plugged (Medium+).
    static func event()     { fire(.levelChange, .medium) }
    /// Tapping a button / toggle / app shortcut (High+).
    static func button()    { fire(.generic, .high) }
    /// Hovering an interactive control (Max only).
    static func hover()     { fire(.alignment, .max) }

    private static func fire(_ pattern: NSHapticFeedbackManager.FeedbackPattern, _ minLevel: HapticLevel) {
        guard Preferences.shared.hapticLevel.rawValue >= minLevel.rawValue else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .default)
    }
}

extension View {
    /// A Max-level hover tick for interactive controls (buttons, tiles, apps).
    func hapticHover() -> some View {
        onHover { if $0 { Haptics.hover() } }
    }
}
