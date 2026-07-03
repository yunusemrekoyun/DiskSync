//
//  SystemMonitorView.swift
//  DiskSync
//
//  The System tab: live CPU / memory / disk usage bars and network throughput.
//  Samples every ~2s only while visible.
//

import SwiftUI

struct SystemMonitorView: View {
    @State private var monitor = SystemMonitor.shared
    @State private var timer = TimerManager.shared

    var body: some View {
        VStack(spacing: 12) {
            meter("cpu", "CPU", "\(Int(monitor.cpuUsage * 100))%",
                  fraction: monitor.cpuUsage, color: .blue)
            meter("memorychip", "Memory",
                  "\(Format.memory(monitor.memoryUsed)) / \(Format.memory(monitor.memoryTotal))",
                  fraction: monitor.memoryFraction, color: .green)
            meter("internaldrive", "Disk",
                  "\(Format.bytes(monitor.diskFree)) free",
                  fraction: monitor.diskUsedFraction, color: .orange)

            HStack {
                Label("\(Format.bytes(Int64(monitor.netDownBytesPerSec)))/s", systemImage: "arrow.down")
                    .foregroundStyle(.cyan)
                Spacer()
                Label("\(Format.bytes(Int64(monitor.netUpBytesPerSec)))/s", systemImage: "arrow.up")
                    .foregroundStyle(.pink)
            }
            .font(.caption.weight(.medium))
            .padding(.top, 2)

            Divider().opacity(0.2)
            timerSection

            Spacer(minLength: 0)
        }
        .padding(16)
        .task {
            // Sample only while this tab is on screen.
            while !Task.isCancelled {
                monitor.sample()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private var timerSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "timer").font(.callout).foregroundStyle(.purple).frame(width: 22)
            if timer.isRunning {
                Text(timer.displayString)
                    .font(.callout.weight(.semibold)).monospacedDigit().foregroundStyle(.white)
                Spacer()
                Button(timer.isPaused ? "Resume" : "Pause") {
                    Haptics.button()
                    if timer.isPaused { timer.resume() } else { timer.pause() }
                }
                .buttonStyle(.bordered).controlSize(.small).hapticHover()
                Button("Stop", role: .destructive) { Haptics.button(); timer.cancel() }
                    .buttonStyle(.bordered).controlSize(.small).hapticHover()
            } else {
                Text("Timer").font(.caption).foregroundStyle(.secondary)
                Spacer()
                ForEach([1, 5, 10, 25], id: \.self) { m in
                    Button("\(m)m") { Haptics.button(); timer.start(minutes: Double(m)) }
                        .buttonStyle(.bordered).controlSize(.small).hapticHover()
                }
            }
        }
    }

    private func meter(_ icon: String, _ title: String, _ value: String,
                       fraction: Double, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.callout).foregroundStyle(color).frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(title).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(value).font(.caption.weight(.medium)).foregroundStyle(.white)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.12))
                        Capsule().fill(color)
                            .frame(width: max(2, geo.size.width * min(1, max(0, fraction))))
                            .animation(.easeInOut, value: fraction)
                    }
                }
                .frame(height: 5)
            }
        }
    }
}
