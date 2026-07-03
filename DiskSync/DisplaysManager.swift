//
//  DisplaysManager.swift
//  ProfessorNotch
//
//  Enumerates the connected displays (CoreGraphics, all public) with their
//  resolution, refresh rate and per-display brightness. Brightness read/write
//  goes through BrightnessManager (private DisplayServices) and is only offered
//  for displays that report a value — external monitors without DDC just show
//  their info.
//

import Foundation
import AppKit
import CoreGraphics

nonisolated struct DisplayInfo: Identifiable, Sendable {
    let id: CGDirectDisplayID
    let name: String
    let width: Int
    let height: Int
    let refreshHz: Int
    let isBuiltin: Bool
    let isMain: Bool
    var brightness: Double?      // nil ⇒ not adjustable for this display

    var resolutionText: String { "\(width) × \(height)" }
}

@MainActor
@Observable
final class DisplaysManager {
    static let shared = DisplaysManager()

    private(set) var displays: [DisplayInfo] = []

    private init() {}

    func refresh() {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
            displays = []
            return
        }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else {
            displays = []
            return
        }

        let brightness = BrightnessManager.shared
        displays = ids.map { id in
            let mode = CGDisplayCopyDisplayMode(id)
            return DisplayInfo(
                id: id,
                name: Self.name(for: id),
                width: mode.map { $0.pixelWidth } ?? Int(CGDisplayPixelsWide(id)),
                height: mode.map { $0.pixelHeight } ?? Int(CGDisplayPixelsHigh(id)),
                refreshHz: Int((mode?.refreshRate ?? 0).rounded()),
                isBuiltin: CGDisplayIsBuiltin(id) != 0,
                isMain: CGDisplayIsMain(id) != 0,
                brightness: brightness.brightness(for: id)
            )
        }
    }

    func setBrightness(_ value: Double, for id: CGDirectDisplayID) {
        BrightnessManager.shared.setBrightness(value, for: id)
        if let idx = displays.firstIndex(where: { $0.id == id }) {
            displays[idx].brightness = min(1, max(0, value))
        }
        // Keep the Control-tab built-in slider in sync.
        if CGDisplayIsBuiltin(id) != 0 { BrightnessManager.shared.refresh() }
    }

    /// A friendly name via the matching NSScreen (falls back to a generic label).
    private static func name(for id: CGDirectDisplayID) -> String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        if let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[key] as? CGDirectDisplayID) == id
        }) {
            return screen.localizedName
        }
        return CGDisplayIsBuiltin(id) != 0 ? "Built-in Display" : "Display"
    }
}
