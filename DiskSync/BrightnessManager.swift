//
//  BrightnessManager.swift
//  ProfessorNotch
//
//  Display brightness for the built-in screen. macOS exposes NO public
//  brightness API on Apple Silicon (IODisplaySetFloatParameter only works on
//  Intel / external DDC), so we call Apple's private DisplayServices framework
//  — the same route menu-bar brightness utilities use. Resolved at runtime via
//  dlopen/dlsym so we never link against a private symbol; if it can't be
//  loaded (future OS change) the control simply reports unavailable.
//

import Foundation
import CoreGraphics

@MainActor
@Observable
final class BrightnessManager {
    static let shared = BrightnessManager()

    /// 0…1 brightness of the built-in display, or nil when unavailable.
    private(set) var level: Double?
    var isAvailable: Bool { level != nil }

    private let builtInDisplay: CGDirectDisplayID?

    private init() {
        builtInDisplay = Self.findBuiltInDisplay()
        refresh()
    }

    func refresh() {
        guard let id = builtInDisplay else { level = nil; return }
        level = brightness(for: id)
    }

    func set(_ newValue: Double) {
        guard let id = builtInDisplay else { return }
        setBrightness(newValue, for: id)
        level = min(1, max(0, newValue))   // reflect immediately; the slider drives this
    }

    /// Brightness (0…1) of any display, or nil if it can't be read (e.g. an
    /// external monitor without DDC support).
    func brightness(for id: CGDirectDisplayID) -> Double? {
        guard let get = Self.getFn else { return nil }
        var value: Float = 0
        return get(id, &value) == 0 ? Double(value) : nil
    }

    func setBrightness(_ value: Double, for id: CGDirectDisplayID) {
        guard let setFn = Self.setFn else { return }
        _ = setFn(id, Float(min(1, max(0, value))))
    }

    // MARK: - Display discovery

    private static func findBuiltInDisplay() -> CGDirectDisplayID? {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return nil }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return nil }
        return ids.first(where: { CGDisplayIsBuiltin($0) != 0 }) ?? ids.first
    }

    // MARK: - Private DisplayServices bridge (resolved once at runtime)

    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let handle: UnsafeMutableRawPointer? =
        dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)

    private static let getFn: GetBrightness? = handle
        .flatMap { dlsym($0, "DisplayServicesGetBrightness") }
        .map { unsafeBitCast($0, to: GetBrightness.self) }

    private static let setFn: SetBrightness? = handle
        .flatMap { dlsym($0, "DisplayServicesSetBrightness") }
        .map { unsafeBitCast($0, to: SetBrightness.self) }
}
