//
//  TimerManager.swift
//  ProfessorNotch
//
//  A simple countdown timer that drives the notch Timer live activity. Uses a
//  wall-clock end date (robust to tick drift / sleep) and publishes the
//  remaining time for the UI.
//

import Foundation

@MainActor
@Observable
final class TimerManager {
    static let shared = TimerManager()
    private init() {}

    private(set) var isRunning = false
    private(set) var isPaused = false
    private(set) var remaining: TimeInterval = 0
    private(set) var total: TimeInterval = 0

    /// Called when the timer starts, is cancelled, or finishes (so the notch can
    /// show/hide the pill immediately). Set by NotchController.
    var onStateChange: (() -> Void)?
    /// Called once when the countdown reaches zero.
    var onFinish: (() -> Void)?

    private var ticker: Timer?
    private var endDate: Date?

    /// Fraction of time remaining (1 → full, 0 → done) for a depleting ring.
    var fraction: Double { total > 0 ? max(0, min(1, remaining / total)) : 0 }

    var displayString: String {
        let s = Int(remaining.rounded(.up))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    func start(minutes: Double) { start(seconds: minutes * 60) }

    func start(seconds: TimeInterval) {
        total = seconds
        remaining = seconds
        isRunning = true
        isPaused = false
        endDate = Date().addingTimeInterval(seconds)
        startTicker()
        onStateChange?()
    }

    func pause() {
        guard isRunning, !isPaused else { return }
        isPaused = true
        ticker?.invalidate(); ticker = nil
        // `remaining` already holds the current value.
    }

    func resume() {
        guard isRunning, isPaused else { return }
        isPaused = false
        endDate = Date().addingTimeInterval(remaining)
        startTicker()
    }

    func cancel() {
        ticker?.invalidate(); ticker = nil
        isRunning = false; isPaused = false; remaining = 0; total = 0; endDate = nil
        onStateChange?()
    }

    private func startTicker() {
        ticker?.invalidate()
        let t = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func tick() {
        guard let endDate else { return }
        remaining = max(0, endDate.timeIntervalSinceNow)
        if remaining <= 0 { finish() }
    }

    private func finish() {
        ticker?.invalidate(); ticker = nil
        isRunning = false; isPaused = false; remaining = 0
        onFinish?()
        onStateChange?()
    }
}
