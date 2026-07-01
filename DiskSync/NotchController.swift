//
//  NotchController.swift
//  DiskSync
//
//  Owns the notch HUD window. The window is fixed-size and always present; the
//  grow/shrink animation happens inside SwiftUI (NotchShell) driven by
//  `NotchViewModel.isExpanded`. While collapsed the window is click-through.
//
//  Hover is detected by mouse-location monitors (global + local) rather than a
//  tracking hand-off, so moving the cursor into the panel keeps it open.
//

import AppKit
import SwiftUI

@MainActor
final class NotchController {
    private let appState: AppState
    private let model = NotchViewModel()

    private var window: NSPanel?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var hideWorkItem: DispatchWorkItem?

    // Geometry (screen coordinates, bottom-left origin — matches NSEvent.mouseLocation).
    private var notchRect: NSRect = .zero
    private var hotRect: NSRect = .zero

    private let panelWidth: CGFloat = 420
    private let panelHeight: CGFloat = 250

    init(app: AppState) {
        self.appState = app
    }

    // MARK: - Install

    func install() {
        guard let screen = Self.notchScreen() else { return }
        let metrics = Self.metrics(for: screen)
        notchRect = metrics.notchRect

        buildWindow(metrics: metrics)
        startMouseMonitors()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild() }
        }
    }

    private func rebuild() {
        stopMouseMonitors()
        window?.orderOut(nil)
        window = nil
        model.isExpanded = false
        install()
    }

    // MARK: - Window

    private func buildWindow(metrics: NotchMetrics) {
        let geometry = NotchGeometry(
            panelWidth: panelWidth,
            panelHeight: panelHeight,
            notchWidth: max(metrics.notchRect.width, 150),
            notchHeight: metrics.notchHeight
        )

        let shell = NotchShell(app: appState, model: model, geometry: geometry)
        let hosting = NSHostingView(rootView: AnyView(shell))

        // Window hugs the top of the screen; SwiftUI pins content to the top,
        // so the shell hangs straight down from the notch.
        let x = metrics.notchRect.midX - panelWidth / 2
        let y = metrics.screenFrame.maxY - panelHeight
        let frame = NSRect(x: x, y: y, width: panelWidth, height: panelHeight)

        let window = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isFloatingPanel = true
        window.level = .statusBar
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.hidesOnDeactivate = false
        window.ignoresMouseEvents = true          // click-through while collapsed
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.contentView = hosting
        window.setFrame(frame, display: true)
        window.orderFrontRegardless()

        // While open, the whole window is the interactive panel.
        hotRect = frame.insetBy(dx: -8, dy: -8).union(metrics.notchRect)

        self.window = window
    }

    // MARK: - Mouse monitors

    private func startMouseMonitors() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { _ in
            MainActor.assumeIsolated { NotchController.current?.handleMouseMove() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { event in
            MainActor.assumeIsolated { NotchController.current?.handleMouseMove() }
            return event
        }
        NotchController.current = self
    }

    private func stopMouseMonitors() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }

    private static weak var current: NotchController?

    private func handleMouseMove() {
        let location = NSEvent.mouseLocation
        if model.isExpanded {
            if hotRect.contains(location) { cancelHide() } else { scheduleHide() }
        } else if notchRect.contains(location) {
            cancelHide()
            expand()
        }
    }

    // MARK: - Expand / collapse

    private func expand() {
        guard !model.isExpanded else { return }
        window?.ignoresMouseEvents = false   // become interactive immediately
        model.isExpanded = true              // SwiftUI runs the spring
    }

    private func collapse() {
        guard model.isExpanded else { return }
        model.isExpanded = false
        window?.ignoresMouseEvents = true    // click-through again
    }

    private func scheduleHide() {
        guard hideWorkItem == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.hideWorkItem = nil
            self?.collapse()
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func cancelHide() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
    }

    // MARK: - Geometry

    private struct NotchMetrics {
        var screenFrame: NSRect
        var notchRect: NSRect
        var notchHeight: CGFloat
    }

    private static func notchScreen() -> NSScreen? {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main
    }

    private static func metrics(for screen: NSScreen) -> NotchMetrics {
        let frame = screen.frame
        let notchHeight = max(screen.safeAreaInsets.top, 32)

        let notchRect: NSRect
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            let x = left.maxX
            let width = right.minX - left.maxX
            notchRect = NSRect(x: x, y: frame.maxY - notchHeight, width: width, height: notchHeight)
        } else {
            let width: CGFloat = 200
            notchRect = NSRect(x: frame.midX - width / 2,
                               y: frame.maxY - notchHeight,
                               width: width, height: notchHeight)
        }
        return NotchMetrics(screenFrame: frame, notchRect: notchRect, notchHeight: notchHeight)
    }
}
