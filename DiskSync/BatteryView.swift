//
//  BatteryView.swift
//  DiskSync
//
//  The Battery tab: a big charge ring plus health / charging details, and a
//  shortcut to Low Power Mode (opened in System Settings, since it can't be
//  toggled programmatically). Also defines the small ring used as the tab icon.
//

import SwiftUI

/// A circular charge ring with the percentage in the middle. Reused at tab-icon
/// size and at detail size.
struct BatteryRing: View {
    let level: Int
    let color: Color
    let diameter: CGFloat
    var showBolt: Bool = false

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.15), lineWidth: diameter * 0.10)
            Circle()
                .trim(from: 0, to: max(0.001, CGFloat(level) / 100))
                .stroke(color, style: StrokeStyle(lineWidth: diameter * 0.10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut, value: level)
            if showBolt {
                VStack(spacing: 0) {
                    Image(systemName: "bolt.fill").font(.system(size: diameter * 0.22, weight: .bold))
                    Text("\(level)").font(.system(size: diameter * 0.26, weight: .bold))
                }
                .foregroundStyle(.white)
            } else {
                Text("\(level)")
                    .font(.system(size: diameter * 0.32, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: diameter, height: diameter)
    }
}

struct BatteryView: View {
    @State private var battery = BatteryManager.shared

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 6) {
                BatteryRing(level: battery.level,
                            color: Color(nsColor: battery.ringColor),
                            diameter: 96,
                            showBolt: battery.isCharging)
                Label(battery.state.label, systemImage: stateSymbol)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color(nsColor: battery.ringColor))
                    .labelStyle(.titleAndIcon)
            }

            VStack(alignment: .leading, spacing: 7) {
                if let h = battery.healthPercent { row("Health", "\(h)%") }
                if let c = battery.cycleCount { row("Cycles", "\(c)") }
                if let t = battery.timeToFullMinutes { row("Time to full", Self.duration(minutes: t)) }
                if let t = battery.timeToEmptyMinutes { row("Time left", Self.duration(minutes: t)) }
                if battery.isPluggedIn, let since = battery.pluggedInSince {
                    row("Plugged in", Self.elapsed(since))
                }
                row("Low Power", battery.isLowPowerMode ? "On" : "Off")

                Button {
                    battery.openBatterySettings()
                } label: {
                    Label("Low Power Mode…", systemImage: "leaf.fill")
                        .font(.caption)
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }

    private var stateSymbol: String {
        switch battery.state {
        case .charging:           return "bolt.fill"
        case .charged:            return "bolt.badge.checkmark"
        case .pluggedNotCharging: return "powerplug.fill"
        case .onBattery:          return "battery.100"
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption.weight(.medium)).foregroundStyle(.white)
        }
    }

    private static func duration(minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    private static func elapsed(_ since: Date) -> String {
        duration(minutes: max(0, Int(Date().timeIntervalSince(since) / 60)))
    }
}
