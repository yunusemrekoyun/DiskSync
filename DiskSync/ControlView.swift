//
//  ControlView.swift
//  ProfessorNotch
//
//  The Control tab — a mini Control-Center in the notch. Left: a now-playing
//  card (no scrubber). Right: brightness + volume sliders and a tappable output
//  device chip. Bottom: four quick-toggle tiles (Wi-Fi, Bluetooth, Dark Mode,
//  Displays). Tapping the output chip or a toggle slides in a detail panel.
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
            audio.refresh()
            while !Task.isCancelled {
                await media.refresh(); refreshSystem()
                try? await Task.sleep(for: media.hasTrack ? .seconds(1.5) : .seconds(4))
            }
        }
    }

    private var move: AnyTransition { .move(edge: .trailing).combined(with: .opacity) }

    private func refreshSystem() {
        brightness.refresh(); net.refresh(); appearance.refresh(); audio.refresh()
        if panel == .displays { displays.refresh() }
    }

    // MARK: - Home

    private var home: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                nowPlayingCard
                controlsCard.frame(width: 214)
            }
            .frame(maxHeight: .infinity)
            togglesRow
        }
    }

    // MARK: - Now playing (left card)

    private var nowPlayingCard: some View {
        Group {
            if media.automationDenied {
                cardEmpty(icon: "lock.shield", title: "Allow media control",
                          action: ("Open Settings", { media.openAutomationSettings() }))
            } else if media.hasTrack {
                VStack(spacing: 14) {
                    HStack(spacing: 10) {
                        artwork
                        VStack(alignment: .leading, spacing: 2) {
                            Text(media.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text(media.artist.isEmpty ? media.source.displayName : media.artist)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Spacer(minLength: 0)
                    }
                    HStack(spacing: 28) {
                        transport("backward.fill") { await media.previous() }
                        transport(media.isPlaying ? "pause.fill" : "play.fill", size: 24) { await media.playPause() }
                        transport("forward.fill") { await media.next() }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                cardEmpty(icon: "music.note", title: "Nothing playing", action: nil)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(12)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
        .frame(width: 54, height: 54)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
        .onTapGesture { if media.hasTrack { Haptics.select(); media.openSourceApp() } }
        .help("Open in \(media.source.displayName)")
    }

    private func cardEmpty(icon: String, title: String, action: (String, () -> Void)?) -> some View {
        VStack(spacing: 7) {
            Image(systemName: icon).font(.title2).foregroundStyle(.secondary)
            Text(title).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let action {
                Button(action.0, action: action.1).buttonStyle(.glass).font(.caption2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func transport(_ symbol: String, size: CGFloat = 16, action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            Image(systemName: symbol)
                .font(.system(size: size))
                .foregroundStyle(.white)
                .frame(width: size + 12, height: size + 12)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Sliders + output (right column)

    private var controlsCard: some View {
        VStack(spacing: 12) {
            if brightness.isAvailable {
                labeledSlider(icon: "sun.max.fill", title: "Brightness",
                              value: brightness.level ?? 0) { brightness.set($0) }
            }
            labeledSlider(icon: volumeIcon, title: "Volume",
                          value: media.volume) { media.setVolume($0) }
            outputChip
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(12)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func labeledSlider(icon: String, title: String, value: Double,
                               onChange: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            CCSlider(value: value, icon: icon, onChange: onChange)
        }
    }

    private var volumeIcon: String {
        if media.volume <= 0.001 { return "speaker.slash.fill" }
        if media.volume < 0.34 { return "speaker.wave.1.fill" }
        if media.volume < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    private var currentOutputName: String {
        audio.outputs.first { $0.id == audio.currentID }?.name ?? "Output"
    }

    private var outputChip: some View {
        Button { audio.refresh(); panel = .audio } label: {
            HStack(spacing: 8) {
                Image(systemName: "hifispeaker.and.appletv").font(.system(size: 13)).foregroundStyle(.secondary)
                Text(currentOutputName).font(.caption.weight(.medium)).foregroundStyle(.white).lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10).frame(height: 30)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Output device")
    }

    // MARK: - Quick toggles (bottom)

    private var togglesRow: some View {
        HStack(spacing: 8) {
            tile(icon: net.wifiOn ? "wifi" : "wifi.slash", label: "Wi-Fi",
                 on: net.wifiOn) { panel = .wifi }
            tile(icon: "dot.radiowaves.right", label: "Bluetooth",
                 on: net.bluetoothOn) { panel = .bluetooth }
            tile(icon: appearance.isDark ? "moon.fill" : "sun.max.fill", label: "Appearance",
                 on: appearance.isDark) { Haptics.select(); appearance.toggle() }
            tile(icon: "display", label: "Displays",
                 on: false) { displays.refresh(); panel = .displays }
        }
    }

    private func tile(icon: String, label: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(on ? .white : .secondary)
                    .frame(width: 34, height: 34)
                    .background {
                        Circle().fill(on ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.white.opacity(0.14)))
                    }
                Text(label).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                            .padding(.vertical, 6).padding(.horizontal, 8)
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
        VStack(spacing: 12) {
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
        VStack(spacing: 12) {
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
                VStack(spacing: 8) {
                    ForEach(displays.displays) { d in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: d.isBuiltin ? "laptopcomputer" : "display")
                                    .foregroundStyle(.secondary)
                                Text(d.name).font(.callout.weight(.medium)).lineLimit(1)
                                Spacer()
                                if d.isMain { Text("Main").font(.caption2).foregroundStyle(.secondary) }
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
                        .padding(10)
                        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}

/// A Control-Center-style horizontal slider: a rounded capsule that fills from
/// the left as you drag, with the level icon inside on the leading edge.
struct CCSlider: View {
    let value: Double
    let icon: String
    let onChange: (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let fill = min(w, max(0, w * value))
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.16))
                Capsule().fill(.white).frame(width: fill)
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(value > 0.14 ? Color.black.opacity(0.55) : .white.opacity(0.85))
                    .padding(.leading, 11)
                    .animation(.easeInOut(duration: 0.15), value: fill)
            }
            .frame(height: 30)
            .clipShape(Capsule())
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in onChange(min(1, max(0, g.location.x / w))) }
            )
        }
        .frame(height: 30)
    }
}
