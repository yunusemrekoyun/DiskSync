//
//  LoginItem.swift
//  DiskSync
//
//  "Open at login" via ServiceManagement's SMAppService. Reflects the real
//  registration state rather than a stored boolean.
//

import Foundation
import ServiceManagement

enum LoginItem {
    /// True when the app is currently registered to launch at login.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Register or unregister the main app as a login item.
    static func setEnabled(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        if enabled {
            if service.status != .enabled {
                try service.register()
            }
        } else {
            if service.status == .enabled {
                try service.unregister()
            }
        }
    }
}
