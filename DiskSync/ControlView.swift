//
//  ControlView.swift
//  ProfessorNotch
//
//  The Control tab — a mini Control-Center in the notch. Left: a compact
//  now-playing mini-player (no scrubber). Right: vertical volume + brightness
//  sliders. Bottom: four round quick toggles (Wi-Fi, Bluetooth, Dark Mode,
//  Displays). Tapping a toggle or the speaker icon slides in a detail panel.
//

import SwiftUI

struct ControlView: View {
    @State private var media = MediaController.shared
    @State private var audio = AudioManager.shared
    @State private var brightness = BrightnessManager.shared
    @State private var net = ConnectivityManager.shared
    @State private var appearance = AppearanceManager.shared
    @State private var displays = DisplaysManager.shared

    private enum Panel: Equatable { case none, audio, wifi, bluetooth, displays }
    @State private var panel: Panel = .none

    var body: some View {
        ZStack {
            switch panel {
            case .none:      home.transition(.opacity)
            case .audio:     audioPanel.transition(move)
            case .wifi:      wifiPanel.transition(move)
            case .bluetooth: bluetoothPanel.transition(move)
            case .displays:  displaysPanel.transition(move)
            }
        }
        .padding(12)
        .animation(.snappy(duration: 0.22), value: panel)
        .task {
            // Snapshot system state on open, then keep it fresh while visible.
            while !Task.isCancelled {
                await media.refresh(); refreshSystem()
                try? await Task.sleep(for: media.hasTrack ? .seconds(1.5) : .seconds(4))
            }
        }
    }

    private var move: AnyTransition { .move(edge: .trailing).combined(with: .opacity) }

    private func refreshSystem() {
        brightness.refresh(); net.refresh(); appearance.refresh()
        if panel == .displays { displays.refresh() }
    }

    // MARK: - Home

    private var home: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                miniPlayer
                    .frame(maxWidth: .infinity, alignment: .leading)
                sliders
            }
            .frame(maxHeight: .infinity)
            quickToggles
        }
    }

    // MARK: - Mini player (left)

    private var miniPlayer: some View {
        Group {
            if media.automationDenied {
                deniedPlayer
            } else if media.hasTrack {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        artwork
                        VStack(alignment: .leading, spacing: 2) {
                            Text(media.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text(media.artist.isEmpty ? media.source.displayName : media.artist)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    HStack(spacing: 22) {
                        transport("backward.fill") { await media.previous() }
                        transport(media.isPlaying ? "pause.fill" : "play.fill", size: 24) { await media.playPause() }
                        transport("forward.fill") { await media.next() }
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                emptyPlayer
            }
        }
    }

    private var artwork: some View {
        Group {
            if let art = media.artwork {
                Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
            } else if let icon = media.appIcon {
                Image(nsImage: icon).resizable()
            } else {
                ZStack {
                    LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "music.note").foregroundStyle(.white.opacity(0.9))
                }
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
        .onTapGesture { if media.hasTrack { Haptics.select(); media.openSourceApp() } }
        .help("Open in \(media.source.displayName)")
    }

    private var emptyPlayer: some View {
        VStack(spacing: 6) {
            Image(systemName: "music.note").font(.title2).foregroundStyle(.secondary)
            Text("Nothing playing").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var deniedPlayer: some View {
        VStack(spacing: 6) {
            Image(systemName: "lock.shield").font(.title3).foregroundStyle(.secondary)
            Text("Allow media control").font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Settings") { media.openAutomationSettings() }
                .buttonStyle(.glass).font(.caption2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func transport(_ symbol: String, size: CGFloat = 17, action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            Image(systemName: symbol)
                .font(.system(size: size))
                .foregroundStyle(.white)
                .frame(width: size + 10, height: size + 10)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Sliders (right)

    private var sliders: some View {
        HStack(spacing: 10) {
            VControlSlider(value: media.volume, systemImage: volumeIcon) { media.setVolume($0) }
                .overlay(alignment: .top) {
                    // Tap the speaker cap to pick the output device.
                    Button { audio.refresh(); panel = .audio } label: {
                        Color.clear.frame(height: 26).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Output device")
                }
            if brightness.isAvailable {
                VControlSlider(value: brightness.level ?? 0, systemImage: "sun.max.fill") { brightness.set($0) }
            }
        }
        .frame(width: brightness.isAvailable ? 96 : 44)
    }

    private var volumeIcon: String {
        if media.volume <= 0.001 { return "speaker.slash.fill" }
        if media.volume < 0.34 { return "speaker.wave.1.fill" }
        if media.volume < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    // MARK: - Quick toggles (bottom)

    private var quickToggles: some View {
        HStack(spacing: 14) {
            toggleButton(icon: net.wifiOn ? "wifi" : "wifi.slash",
                         on: net.wifiOn, label: "Wi-Fi") { panel = .wifi }
            toggleButton(icon: "dot.radiowaves.right",
                         on: net.bluetoothOn, label: "Bluetooth") { panel = .bluetooth }
            toggleButton(icon: appearance.isDark ? "moon.fill" : "sun.max.fill",
                         on: appearance.isDark, label: "Appearance") { Haptics.select(); appearance.toggle() }
            toggleButton(icon: "display", on: false, label: "Displays") {
                displays.refresh(); panel = .displays
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func toggleButton(icon: String, on: Bool, label: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 4) {
            Button(action: action) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(on ? .white : .secondary)
                    .frame(width: 46, height: 46)
                    .background {
                        Circle().fill(on ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.white.opacity(0.14)))
                    }
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            Text(label).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    // MARK: - Detail panels

    private func panelHeader(_ title: String) -> some View {
        HStack {
            Button { panel = .none } label: {
                Image(systemName: "chevron.left").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            Spacer()
            Text(title).font(.headline)
            Spacer()
            Spacer().frame(width: 16)
        }
    }

    private var audioPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            panelHeader("Output")
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(audio.outputs) { device in
                        Button { audio.select(device) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: audio.symbol(for: device)).frame(width: 22)
                                    .foregroundStyle(device.id == audio.currentID ? Color.accentColor : .secondary)
                                Text(device.name).foregroundStyle(.white).lineLimit(1)
                                Spacer()
                                if device.id == audio.currentID {
                                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                                }
                            }
                            .padding(.vertical, 5).padding(.horizontal, 8)
                            .background(device.id == audio.currentID ? AnyShapeStyle(.white.opacity(0.08)) : AnyShapeStyle(.clear),
                                        in: RoundedRectangle(cornerRadius: 8))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var wifiPanel: some View {
        VStack(spacing: 10) {
            panelHeader("Wi-Fi")
            Toggle("Wi-Fi", isOn: Binding(get: { net.wifiOn }, set: { net.setWiFi($0) }))
                .toggleStyle(.switch)
                .disabled(!net.wifiAvailable)
            Button { net.openWiFiSettings() } label: {
                Label("Wi-Fi Settings…", systemImage: "gearshape").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            Spacer(minLength: 0)
        }
    }

    private var bluetoothPanel: some View {
        VStack(spacing: 10) {
            panelHeader("Bluetooth")
            Toggle("Bluetooth", isOn: Binding(get: { net.bluetoothOn }, set: { net.setBluetooth($0) }))
                .toggleStyle(.switch)
                .disabled(!net.bluetoothToggleable)
            if !net.bluetoothToggleable {
                Text("Toggle unavailable on this Mac.").font(.caption2).foregroundStyle(.secondary)
            }
            Button { net.openBluetoothSettings() } label: {
                Label("Bluetooth Settings…", systemImage: "gearshape").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            Spacer(minLength: 0)
        }
    }

    private var displaysPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            panelHeader("Displays")
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(displays.displays) { d in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: d.isBuiltin ? "laptopcomputer" : "display")
                                    .foregroundStyle(.secondary)
                                Text(d.name).font(.callout.weight(.medium)).lineLimit(1)
                                Spacer()
                                Text(d.isMain ? "Main" : "").font(.caption2).foregroundStyle(.secondary)
                            }
                            Text("\(d.resolutionText)\(d.refreshHz > 0 ? " · \(d.refreshHz) Hz" : "")")
                                .font(.caption2).foregroundStyle(.secondary)
                            if let b = d.brightness {
                                HStack(spacing: 8) {
                                    Image(systemName: "sun.min").font(.caption2).foregroundStyle(.secondary)
                                    Slider(value: Binding(get: { b },
                                                          set: { displays.setBrightness($0, for: d.id) }))
                                    Image(systemName: "sun.max").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(8)
                        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}

/// A Control-Center-style vertical slider: a rounded bar that fills from the
/// bottom as you drag, with a level icon near the base.
struct VControlSlider: View {
    let value: Double
    let systemImage: String
    let onChange: (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let fill = min(h, max(0, h * value))
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(0.16))
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white)
                    .frame(height: fill)
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(value > 0.14 ? Color.black.opacity(0.55) : .white.opacity(0.85))
                    .padding(.bottom, 9)
                    .animation(.easeInOut(duration: 0.15), value: fill)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in onChange(min(1, max(0, 1 - g.location.y / h))) }
            )
        }
        .frame(width: 42)
    }
}
