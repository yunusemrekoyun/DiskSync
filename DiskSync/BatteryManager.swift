//
//  BatteryManager.swift
//  DiskSync
//
//  Reads battery state, health and charging info from the values macOS already
//  maintains (IOKit power sources + AppleSmartBattery) — we never measure
//  anything ourselves. Updates are event-driven via IOPS notifications (no
//  polling), so it's essentially free.
//

import Foundation
import AppKit
import IOKit
import IOKit.ps

nonisolated enum ChargeState: Sendable {
    case onBattery          // running on battery
    case charging           // plugged in, battery filling
    case charged            // plugged in, full
    case pluggedNotCharging // plugged in (AC) but not charging the battery

    var label: String {
        switch self {
        case .onBattery:          return "On battery"
        case .charging:           return "Charging"
        case .charged:            return "Charged"
        case .pluggedNotCharging: return "Plugged in, not charging"
        }
    }
}

@MainActor
@Observable
final class BatteryManager {
    static let shared = BatteryManager()

    var level: Int = 0                 // 0…100
    var state: ChargeState = .onBattery
    var isLowPowerMode = false
    var timeToFullMinutes: Int?        // while charging
    var timeToEmptyMinutes: Int?       // while on battery
    var healthPercent: Int?            // maximum capacity vs design
    var cycleCount: Int?
    var pluggedInSince: Date?          // since we observed AC (approx.)

    /// Fires when the AC connection changes (true = just plugged in).
    var onPlugChange: ((Bool) -> Void)?

    private var runLoopSource: CFRunLoopSource?
    private var wasPluggedIn = false

    var isPluggedIn: Bool { state != .onBattery }
    var isCharging: Bool { state == .charging }

    /// Ring color per the requested rules.
    var ringColor: NSColor {
        if isCharging { return .systemGreen }
        if isLowPowerMode { return .systemYellow }
        if level < 20 { return .systemRed }
        return .white
    }

    private init() {
        isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        refresh()
        start()

        NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
        }
    }

    // MARK: - Live updates (event-driven, no polling)

    private func start() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource(Self.psCallback, context)?.takeRetainedValue() else { return }
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    }

    private static let psCallback: IOPowerSourceCallbackType = { context in
        guard let context else { return }
        let manager = Unmanaged<BatteryManager>.fromOpaque(context).takeUnretainedValue()
        Task { @MainActor in manager.refresh() }
    }

    /// Open macOS Battery settings (Low Power Mode isn't togglable via public API).
    func openBatterySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Reads

    func refresh() {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return }

        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any] else { continue }

            let current = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maximum = desc[kIOPSMaxCapacityKey] as? Int ?? 100
            level = maximum > 0 ? Int((Double(current) / Double(maximum) * 100).rounded()) : current

            let onAC = (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            let charging = desc[kIOPSIsChargingKey] as? Bool ?? false
            let charged = desc[kIOPSIsChargedKey] as? Bool ?? false

            if !onAC {
                state = .onBattery
            } else if charged {
                state = .charged
            } else if charging {
                state = .charging
            } else {
                state = .pluggedNotCharging
            }

            let ttf = desc["Time to Full"] as? Int ?? -1
            let tte = desc[kIOPSTimeToEmptyKey] as? Int ?? -1
            timeToFullMinutes = ttf > 0 ? ttf : nil
            timeToEmptyMinutes = tte > 0 ? tte : nil
            break   // the internal battery is the first/only relevant source
        }

        // Track AC connection transitions (approximate "plugged in since").
        let pluggedNow = isPluggedIn
        if pluggedNow != wasPluggedIn {
            wasPluggedIn = pluggedNow
            pluggedInSince = pluggedNow ? Date() : nil
            onPlugChange?(pluggedNow)
        } else if pluggedNow && pluggedInSince == nil {
            pluggedInSince = Date()
        }

        // Health & cycle count change slowly; refreshing on power events keeps
        // them from going stale over a long-running session.
        readHealth()
    }

    /// Battery health & cycle count from AppleSmartBattery (system-provided).
    private func readHealth() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }

        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let props = unmanaged?.takeRetainedValue() as? [String: Any] else { return }

        cycleCount = props["CycleCount"] as? Int

        // Match System Settings' "Maximum Capacity": it uses the nominal full-
        // charge capacity, not the rawer AppleRawMaxCapacity (which reads low).
        let fullCharge = (props["NominalChargeCapacity"] as? Int)
            ?? (props["AppleRawMaxCapacity"] as? Int)
            ?? (props["MaxCapacity"] as? Int)
        let designCap = props["DesignCapacity"] as? Int
        if let full = fullCharge, let design = designCap, design > 0 {
            healthPercent = min(100, Int((Double(full) / Double(design) * 100).rounded()))
        }
    }
}
