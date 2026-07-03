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
    private var dropWindow: NSWindow?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var hideWorkItem: DispatchWorkItem?
    private var flashClearItem: DispatchWorkItem?

    // Live Activities (Dynamic-Island-style collapsed-notch info).
    private var downloadWatcher: FolderWatcher?
    private var liveTask: Task<Void, Never>?
    private let downloadsDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Downloads")

    // Geometry (screen coordinates, bottom-left origin — matches NSEvent.mouseLocation).
    private var notchRect: NSRect = .zero
    private var hotRect: NSRect = .zero

    private let panelWidth: CGFloat = 480
    private let panelHeight: CGFloat = 250

    init(app: AppState) {
        self.appState = app
        // Briefly drop the notch open when the charger is (un)plugged.
        BatteryManager.shared.onPlugChange = { [weak self] plugged in
            self?.flashPower(plugged)
        }
    }

    private func flashPower(_ plugged: Bool) {
        let battery = BatteryManager.shared
        let kind: FlashKind
        if !plugged {
            kind = .unplugged
        } else {
            switch battery.state {
            case .charging:           kind = .charging
            case .charged:            kind = .charged
            case .pluggedNotCharging: kind = .pluggedNotCharging
            case .onBattery:          kind = .unplugged
            }
        }
        showFlash(NotchFlash(kind: kind, level: battery.level))
        Haptics.event()   // tick when charger is (un)plugged
    }

    /// Show a transient flash (charge/volume/download) that overrides any live
    /// activity for `duration`, then reverts.
    private func showFlash(_ flash: NotchFlash, duration: TimeInterval = 2.8) {
        guard window != nil else { return }   // nothing to show without a HUD window
        model.flash = flash
        flashClearItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.model.flash = nil }
        flashClearItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    // MARK: - Live Activities

    private func startLiveActivities() {
        // Poll the media state slowly so the Now Playing pill can appear/leave
        // even while the notch is collapsed (there is no public push for
        // system playback). Gated by the preference so it can be turned off.
        if liveTask == nil {
            // Show/hide the pill immediately when a timer starts/stops.
            TimerManager.shared.onStateChange = { [weak self] in self?.updateActivity() }
            TimerManager.shared.onFinish = { [weak self] in self?.timerFinished() }
            liveTask = Task { [weak self] in
                while !Task.isCancelled {
                    let prefs = Preferences.shared
                    if prefs.liveActivitiesEnabled, prefs.laNowPlaying {
                        await MediaController.shared.refreshPlayback()
                    }
                    self?.updateActivity()
                    try? await Task.sleep(for: .seconds(8))
                }
            }
        }
        // Watch ~/Downloads for finished downloads.
        if downloadWatcher == nil {
            let watcher = FolderWatcher(paths: [downloadsDir.path], latency: 0.5, debounce: 1.0) { [weak self] changed in
                Task { @MainActor in self?.handleDownloadChanges(changed) }
            }
            watcher.start()
            downloadWatcher = watcher
        }
    }

    /// Pick the persistent activity for the collapsed notch (priority order).
    private func updateActivity() {
        let prefs = Preferences.shared
        guard prefs.liveActivitiesEnabled, !model.isExpanded else { model.activity = nil; return }
        let media = MediaController.shared
        if prefs.laTimer, TimerManager.shared.isRunning {
            model.activity = .timer
        } else if prefs.laNowPlaying, media.hasTrack, media.isPlaying {
            model.activity = .nowPlaying
        } else {
            model.activity = nil
        }
    }

    private func timerFinished() {
        updateActivity()   // drop the timer pill (isRunning is now false)
        showFlash(NotchFlash(kind: .timerDone), duration: 4)
        Haptics.event()
        Task { await Notifier.post(title: "Timer done", body: "Your timer has finished.", enabled: true) }
    }

    /// A batch of ~/Downloads changes arrived — flash the newest finished file.
    private func handleDownloadChanges(_ changed: Set<String>) {
        let prefs = Preferences.shared
        guard prefs.liveActivitiesEnabled, prefs.laDownloads else { return }
        let tempExt: Set<String> = ["crdownload", "download", "part", "tmp", "opdownload", "aria2"]
        var best: (name: String, date: Date)?
        let now = Date()
        for path in changed {
            let url = URL(fileURLWithPath: path)
            guard url.deletingLastPathComponent().path == downloadsDir.path else { continue }  // top-level only
            let name = url.lastPathComponent
            if name.hasPrefix(".") || tempExt.contains(url.pathExtension.lowercased()) { continue }
            guard let rv = try? url.resourceValues(forKeys: [.isRegularFileKey, .addedToDirectoryDateKey, .contentModificationDateKey]),
                  rv.isRegularFile == true else { continue }
            let added = rv.addedToDirectoryDate ?? rv.contentModificationDate ?? .distantPast
            guard now.timeIntervalSince(added) < 15 else { continue }   // freshly landed
            if best == nil || added > best!.date { best = (name, added) }
        }
        if let best {
            showFlash(NotchFlash(kind: .download, text: best.name))
            Haptics.event()
        }
    }

    // MARK: - Install

    func install() {
        // Register the screen-change observer exactly once (install() re-runs on
        // every rebuild — adding it each time would compound observers/rebuilds).
        if screenObserver == nil {
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.rebuild() }
            }
        }

        guard let screen = Self.notchScreen() else {
            notchRect = .zero
            hotRect = .zero
            return
        }
        let metrics = Self.metrics(for: screen)
        notchRect = metrics.notchRect

        buildWindow(metrics: metrics)
        buildDropWindow(metrics: metrics)
        startMouseMonitors()
        startLiveActivities()
    }

    private func rebuild() {
        stopMouseMonitors()
        cancelHide()
        flashClearItem?.cancel()
        window?.orderOut(nil)
        dropWindow?.orderOut(nil)
        window = nil
        dropWindow = nil
        model.isExpanded = false
        model.flash = nil
        model.activity = nil
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
        // FirstMouse hosting view so a click registers on the *first* tap even
        // though the panel is non-activating (otherwise the first click is
        // eaten to "focus" the window and tabs need a second click).
        let hosting = FirstMouseHostingView(rootView: AnyView(shell))

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
        window.acceptsMouseMovedEvents = true     // so hover monitors fire over it
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.contentView = hosting
        window.setFrame(frame, display: true)
        window.orderFrontRegardless()

        // While open, the whole window is the interactive panel.
        hotRect = frame.insetBy(dx: -8, dy: -8).union(metrics.notchRect)

        self.window = window
    }

    /// A small always-present window over the notch that accepts file drags —
    /// the reliable way to detect a drag (NSEvent monitors go silent during a
    /// drag session). Dragging a file here opens the Shelf and drops onto it.
    private func buildDropWindow(metrics: NotchMetrics) {
        // Keep the drop zone within the notch's tab-free center — clamped to 200
        // so even a wide (16-inch) notch never overlaps the innermost tab icons.
        let width = min(max(metrics.notchRect.width, 120), 200)
        let height = metrics.notchHeight + 16
        let frame = NSRect(x: metrics.notchRect.midX - width / 2,
                           y: metrics.screenFrame.maxY - height,
                           width: width, height: height)

        let detector = DropDetectorView(frame: NSRect(origin: .zero, size: frame.size))
        detector.onEnter = { [weak self] in self?.openForFileDrop() }
        detector.onFiles = { [weak self] urls, command in
            guard let self else { return }
            if command { ShelfStore.shared.airDrop(urls) } else { ShelfStore.shared.add(urls) }
            self.model.tab = .shelf
            self.expand()
            Haptics.event()
        }

        let window = NSWindow(contentRect: frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .statusBar
        window.ignoresMouseEvents = false   // must receive drag events
        window.acceptsMouseMovedEvents = true   // keep hover-to-open working over the notch
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.contentView = detector
        window.orderFrontRegardless()
        self.dropWindow = window
    }

    // MARK: - Mouse monitors

    private func startMouseMonitors() {
        // Hover detection only. File drags are handled by a real dragging
        // destination (NSEvent monitors don't fire during a drag session).
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleMouseMove() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            MainActor.assumeIsolated { self?.handleMouseMove() }
            return event
        }
    }

    private func stopMouseMonitors() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }

    private func handleMouseMove() {
        let location = NSEvent.mouseLocation
        if model.isExpanded {
            if hotRect.contains(location) { cancelHide() } else { scheduleHide() }
        } else if notchRect.contains(location) {
            cancelHide()
            // Unless the user prefers reopening their last tab, a plain hover
            // opens the first (Control) tab — or Sync if Control is hidden.
            if !Preferences.shared.openLastTab {
                model.tab = Preferences.shared.showNowPlaying ? .nowPlaying : .sync
            }
            expand()
        }
    }

    /// Called by the notch drop target when a file drag enters — open the Shelf.
    private func openForFileDrop() {
        cancelHide()
        model.tab = .shelf
        expand()
    }

    // MARK: - Expand / collapse

    private func expand() {
        guard !model.isExpanded else { return }
        // A hover takes over from any in-flight charging flash.
        flashClearItem?.cancel()
        model.flash = nil
        window?.ignoresMouseEvents = false   // become interactive immediately
        model.isExpanded = true              // SwiftUI runs the spring
        Haptics.notchOpen()                  // subtle tick on open
    }

    private func collapse() {
        guard model.isExpanded else { return }
        model.isExpanded = false
        window?.ignoresMouseEvents = true    // click-through again
        updateActivity()                     // show the live pill again right away
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

/// Hosting view that responds to the first click even when its (non-activating)
/// window isn't key — so notch controls act on a single tap.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Invisible view over the notch that accepts file drags: reports enter (to open
/// the Shelf) and the dropped file URLs (with the ⌘ modifier for AirDrop).
final class DropDetectorView: NSView {
    var onEnter: (() -> Void)?
    var onFiles: (([URL], Bool) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    private func hasFiles(_ sender: NSDraggingInfo) -> Bool {
        sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self],
                                                options: [.urlReadingFileURLsOnly: true])
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard hasFiles(sender) else { return [] }
        onEnter?()
        return .copy
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        hasFiles(sender) ? .copy : []
    }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { hasFiles(sender) }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        guard !urls.isEmpty else { return false }
        onFiles?(urls, NSEvent.modifierFlags.contains(.command))
        return true
    }
}
