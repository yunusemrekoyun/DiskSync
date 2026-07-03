//
//  VolumeMonitor.swift
//  DiskSync
//
//  Observes volume mount / unmount via NSWorkspace and reports capacity for
//  the destination. Also exposes a wake-from-sleep hook. Runs on the
//  MainActor since it drives UI state and uses AppKit notifications.
//

import Foundation
import AppKit

@MainActor
final class VolumeMonitor {
    /// Called whenever a volume mounts or unmounts.
    var onVolumeChange: (() -> Void)?
    /// Called when the machine wakes from sleep.
    var onWake: (() -> Void)?

    private var observers: [NSObjectProtocol] = []

    func start() {
        let ws = NSWorkspace.shared.notificationCenter
        observers.append(ws.addObserver(forName: NSWorkspace.didMountNotification,
                                        object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onVolumeChange?() }
        })
        observers.append(ws.addObserver(forName: NSWorkspace.didUnmountNotification,
                                        object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onVolumeChange?() }
        })
        observers.append(ws.addObserver(forName: NSWorkspace.didWakeNotification,
                                        object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onWake?() }
        })
    }

    func stop() {
        let ws = NSWorkspace.shared.notificationCenter
        observers.forEach { ws.removeObserver($0) }
        observers.removeAll()
    }
    // No deinit: VolumeMonitor lives for the whole app lifetime, and its
    // observers are torn down by `stop()`. (A nonisolated deinit may not touch
    // the MainActor-isolated `observers` array under Swift 6.)

    // MARK: - Capacity

    /// Capacity snapshot for the volume that contains `url`. `isConnected`
    /// reflects whether the destination directory currently exists.
    nonisolated static func driveInfo(for url: URL, expectMarker: Bool) -> DriveInfo {
        let fm = FileManager.default
        let connected = fm.fileExists(atPath: url.path) &&
            (!expectMarker || fm.fileExists(atPath: url.appendingPathComponent(Defaults.markerFileName).path))

        guard connected else { return .disconnected }

        let keys: Set<URLResourceKey> = [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
        ]
        let values = try? url.resourceValues(forKeys: keys)
        let total = Int64(values?.volumeTotalCapacity ?? 0)
        let free = values?.volumeAvailableCapacityForImportantUsage
            ?? Int64(values?.volumeAvailableCapacity ?? 0)
        let name = values?.volumeName ?? url.deletingLastPathComponent().lastPathComponent

        return DriveInfo(isConnected: true, volumeName: name, totalBytes: total, freeBytes: free)
    }
}
