//
//  ConnectivityManager.swift
//  ProfessorNotch
//
//  Wi-Fi and Bluetooth power state + toggles for the Control tab.
//
//  Wi-Fi uses the public CoreWLAN framework (CWInterface.setPower).
//  Bluetooth has NO public power toggle, so we call the private
//  IOBluetoothPreference{Get,Set}ControllerPowerState symbols (the same ones
//  `blueutil` uses), resolved at runtime via dlopen/dlsym. If they can't be
//  loaded the Bluetooth button falls back to opening System Settings.
//

import Foundation
import AppKit
import CoreWLAN

@MainActor
@Observable
final class ConnectivityManager {
    static let shared = ConnectivityManager()

    private(set) var wifiOn = false
    private(set) var wifiAvailable = false
    private(set) var bluetoothOn = false
    var bluetoothToggleable: Bool { Self.btSetFn != nil }

    private let wifiClient = CWWiFiClient.shared()

    private init() {
        refresh()
    }

    func refresh() {
        if let iface = wifiClient.interface() {
            wifiAvailable = true
            wifiOn = iface.powerOn()
        } else {
            wifiAvailable = false
        }
        if let get = Self.btGetFn { bluetoothOn = get() != 0 }
    }

    // MARK: - Wi-Fi (public CoreWLAN)

    func setWiFi(_ on: Bool) {
        guard let iface = wifiClient.interface() else { return }
        try? iface.setPower(on)
        wifiOn = on
    }

    func toggleWiFi() { setWiFi(!wifiOn) }

    func openWiFiSettings() {
        open("x-apple.systempreferences:com.apple.wifi-settings-extension")
    }

    // MARK: - Bluetooth (private IOBluetooth symbols)

    func setBluetooth(_ on: Bool) {
        guard let set = Self.btSetFn else { openBluetoothSettings(); return }
        set(on ? 1 : 0)
        bluetoothOn = on
    }

    func toggleBluetooth() { setBluetooth(!bluetoothOn) }

    func openBluetoothSettings() {
        open("x-apple.systempreferences:com.apple.BluetoothSettings")
    }

    private func open(_ urlString: String) {
        if let url = URL(string: urlString) { NSWorkspace.shared.open(url) }
    }

    // MARK: - Private Bluetooth bridge (resolved once at runtime)

    private typealias GetPower = @convention(c) () -> Int32
    private typealias SetPower = @convention(c) (Int32) -> Void

    private static let handle: UnsafeMutableRawPointer? =
        dlopen("/System/Library/Frameworks/IOBluetooth.framework/IOBluetooth", RTLD_NOW)

    private static let btGetFn: GetPower? = handle
        .flatMap { dlsym($0, "IOBluetoothPreferenceGetControllerPowerState") }
        .map { unsafeBitCast($0, to: GetPower.self) }

    private static let btSetFn: SetPower? = handle
        .flatMap { dlsym($0, "IOBluetoothPreferenceSetControllerPowerState") }
        .map { unsafeBitCast($0, to: SetPower.self) }
}
