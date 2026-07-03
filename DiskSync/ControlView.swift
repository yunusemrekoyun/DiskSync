//
//  ControlView.swift
//  ProfessorNotch
//
//  The Control tab — a compact mini Control-Center in the notch. Top: a
//  now-playing strip (no scrubber). Middle: brightness + volume sliders with a
//  visible output-device button. Bottom: four quick-toggle tiles. Wi-Fi and
//  Bluetooth expand a simple inline on/off + Settings row right below the tiles;
//  the output picker and Displays open a sliding detail panel. The whole thing
//  scrolls (top-anchored) so it never clips at the standard HUD height.
//

import SwiftUI

struct ControlView: View {
    @State private var media = MediaController.shared
    @State private var audio = AudioManager.shared
    @State private var brightness = BrightnessManager.shared
    @State private var net = ConnectivityManager.shared
    @State private var appearance = AppearanceManager.shared
    @State private var displays = DisplaysManager.shared

    private enum Panel: Equatable { case none, audio, displays }
    private enum Expanded: Equatable { case wifi, bluetooth }
    @State private var panel: Panel = .none
    @State private var expanded: Expanded?

    var body: some View {
        Group {
            switch panel {
            case .none:     home
            case .audio:    audioPanel.padding(12)
            case .displays: displaysPanel.padding(12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.snappy(duration: 0.22), value: panel)
        .task {
            audio.refresh()
            while !Task.isCancelled {
                await media.refresh(); refreshSystem()
                try? await Task.sleep(for: media.hasTrack ? .seconds(1.5) : .seconds(4))
            }
        }
    }

    private func refreshSystem() {
        brightness.refresh(); net.refresh(); appearance.refresh(); audio.refresh()
        if panel == .displays { displays.refresh() }
    }

    // MARK: - Home

    private var home: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 10) {
                musicStrip
                slidersRow
                togglesRow
                if let expanded {
                    inlineToggle(expanded)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(12)
        }
        .animation(.snappy(duration: 0.22), value: expanded)
    }

    // MARK: - Now playing (top strip)

    private var musicStrip: some View {
        Group {
            if media.automationDenied {
                HStack(spacing: 10) {
                    Image(systemName: "lock.shield").font(.title3).foregroundStyle(.secondary)
                    Text("Allow media control to see what's playing.")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    Spacer(minLength: 4)
                    Button("Settings") { media.openAutomationSettings() }
                        .buttonStyle(.glass).font(.caption2)
                }
            } else if media.hasTrack {
                HStack(spacing: 10) {
                    artwork
                    VStack(alignment: .leading, spacing: 2) {
                        Text(media.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text(media.artist.isEmpty ? media.source.displayName : media.artist)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    HStack(spacing: 14) {
                        transport("backward.fill", size: 13) { await media.previous() }
                        transport(media.isPlaying ? "pause.fill" : "play.fill", size: 20) { await media.playPause() }
                        transport("forward.fill", size: 13) { await media.next() }
                    }
                }
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "music.note").font(.title3).foregroundStyle(.secondary)
                    Text("Nothing playing").font(.callout).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(height: 52)
        .padding(.horizontal, 12)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
        .frame(width: 42, height: 42)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
        .onTapGesture { if media.hasTrack { Haptics.select(); media.openSourceApp() } }
        .help("Open in \(media.source.displayName)")
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

    // MARK: - Sliders + output

    private var slidersRow: some View {
        VStack(spacing: 8) {
            if brightness.isAvailable {
                CCSlider(value: brightness.level ?? 0, icon: "sun.max.fill") { brightness.set($0) }
            }
            HStack(spacing: 8) {
                CCSlider(value: media.volume, icon: volumeIcon) { media.setVolume($0) }
                outputButton
            }
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

    private var outputButton: some View {
        Button { audio.refresh(); panel = .audio } label: {
            Image(systemName: "hifispeaker.and.appletv")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 42, height: 30)
                .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Output: \(currentOutputName)")
    }

    // MARK: - Quick toggles (bottom)

    private var togglesRow: some View {
        HStack(spacing: 8) {
            tile(icon: net.wifiOn ? "wifi" : "wifi.slash", label: "Wi-Fi",
                 on: net.wifiOn, active: expanded == .wifi) { toggleExpanded(.wifi) }
            tile(icon: "dot.radiowaves.right", label: "Bluetooth",
                 on: net.bluetoothOn, active: expanded == .bluetooth) { toggleExpanded(.bluetooth) }
            tile(icon: appearance.isDark ? "moon.fill" : "sun.max.fill", label: "Appearance",
                 on: appearance.isDark, active: false) { Haptics.select(); appearance.toggle() }
            tile(icon: "display", label: "Displays",
                 on: false, active: false) { displays.refresh(); panel = .displays }
        }
    }

    private func toggleExpanded(_ e: Expanded) {
        Haptics.select()
        expanded = (expanded == e) ? nil : e
    }

    private func tile(icon: String, label: String, on: Bool, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(on ? .white : .secondary)
                    .frame(width: 32, height: 32)
                    .background {
                        Circle().fill(on ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.white.opacity(0.14)))
                    }
                Text(label).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(active ? AnyShapeStyle(.white.opacity(0.12)) : AnyShapeStyle(.white.opacity(0.05)),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Inline Wi-Fi / Bluetooth controls

    @ViewBuilder
    private func inlineToggle(_ e: Expanded) -> some View {
        switch e {
        case .wifi:
            inlineRow(title: "Wi-Fi", isOn: net.wifiOn, enabled: net.wifiAvailable,
                      set: { net.setWiFi($0) }, openSettings: { net.openWiFiSettings() })
        case .bluetooth:
            inlineRow(title: "Bluetooth", isOn: net.bluetoothOn, enabled: net.bluetoothToggleable,
                      set: { net.setBluetooth($0) }, openSettings: { net.openBluetoothSettings() })
        }
    }

    private func inlineRow(title: String, isOn: Bool, enabled: Bool,
                           set: @escaping (Bool) -> Void, openSettings: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Toggle(title, isOn: Binding(get: { isOn }, set: set))
                .toggleStyle(.switch)
                .disabled(!enabled)
                .font(.callout)
            Spacer(minLength: 8)
            Button { openSettings() } label: {
                Label("Settings", systemImage: "gearshape").font(.caption)
            }
            .buttonStyle(.glass)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Detail panels (output + displays)

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
            .frame(height: 28)
            .clipShape(Capsule())
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in onChange(min(1, max(0, g.location.x / w))) }
            )
        }
        .frame(height: 28)
    }
}
