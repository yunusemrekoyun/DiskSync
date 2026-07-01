//
//  Haptics.swift
//  DiskSync
//
//  Tiny wrapper around NSHapticFeedbackManager for subtle trackpad feedback.
//  No-op on devices without a Force Touch trackpad; respects system settings.
//

import AppKit

@MainActor
enum Haptics {
    /// Subtle tick when the notch opens.
    static func hover() { perform(.alignment) }
    /// Light feedback when switching tabs / tapping.
    static func select() { perform(.generic) }
    /// Firmer feedback for a completed action (drop, plug-in).
    static func action() { perform(.levelChange) }

    private static func perform(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .default)
    }
}
