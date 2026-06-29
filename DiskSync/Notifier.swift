//
//  Notifier.swift
//  DiskSync
//
//  Thin wrapper around UserNotifications for sync-completion and error
//  summaries. Fully local; no remote push of any kind.
//

import Foundation
import UserNotifications

enum Notifier {
    /// Ask for permission once on first launch. Safe to call repeatedly.
    static func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    /// Post a local notification. `enabled` mirrors the user setting so the
    /// caller can gate without branching.
    static func post(title: String, body: String, enabled: Bool) async {
        guard enabled else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized ||
              settings.authorizationStatus == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = nil

        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content,
                                            trigger: nil)
        try? await center.add(request)
    }
}
