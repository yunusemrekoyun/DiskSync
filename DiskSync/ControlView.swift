//
//  ControlView.swift
//  ProfessorNotch
//
//  The Control tab — a compact mini Control-Center in the notch. Left: a
//  now-playing card. Right: vertical volume + brightness sliders with an output
//  device chip. Bottom: four quick-toggle tiles; Wi-Fi and Bluetooth expand a
//  simple inline on/off + Settings row right below. Everything fits the standard
//  HUD height (a ScrollView is only a safety net when a toggle is expanded).
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
    @Namespace private var tileNS

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
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                musicCard
                rightColumn.frame(width: 118)
            }
            .frame(maxHeight: .infinity)
            togglesRow
        }
        .padding(12)
    }

    // MARK: - Now playing (left card)

    private var musicCard: some View {
        Group {
            if media.automationDenied {
                VStack(spacing: 7) {
                    Image(systemName: "lock.shield").font(.title3).foregroundStyle(.secondary)
                    Text("Allow media control").font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Open Settings") { media.openAutomationSettings() }
                        .buttonStyle(.glass).font(.caption2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if media.hasTrack {
                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        artwork
                        VStack(alignment: .leading, spacing: 2) {
                            Text(media.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text(media.artist.isEmpty ? media.source.displayName : media.artist)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    HStack(spacing: 24) {
                        transport("backward.fill", size: 14) { await media.previous() }
                        transport(media.isPlaying ? "pause.fill" : "play.fill", size: 20) { await media.playPause() }
                        transport("forward.fill", size: 14) { await media.next() }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "music.note").font(.title2).foregroundStyle(.secondary)
                    Text("Nothing playing").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    // MARK: - Sliders + output (right column)

    private var rightColumn: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                VSlider(value: media.volume, icon: volumeIcon) { media.setVolume($0) }
                if brightness.isAvailable {
                    VSlider(value: brightness.level ?? 0, icon: "sun.max.fill") { brightness.set($0) }
                }
            }
            .frame(maxHeight: .infinity)
            outputChip
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
            HStack(spacing: 5) {
                Image(systemName: "hifispeaker.and.appletv").font(.system(size: 11)).foregroundStyle(.secondary)
                Text(currentOutputName).font(.system(size: 10, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8).frame(height: 26).frame(maxWidth: .infinity)
            .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Output: \(currentOutputName)")
    }

    // MARK: - Quick toggles (bottom)
    //
    // Four 1x1 tiles. Tapping Wi-Fi or Bluetooth morphs that tile into a 2x1
    // (sliding to the left) while the other tiles fade out and a 2x1 controls
    // panel (on/off + Settings) appears on the right — all within the same row,
    // so nothing grows downward. Tap the tile again to restore the four tiles.

    private var togglesRow: some View {
        ZStack {
            if let expanded {
                expandedRow(expanded)
            } else {
                collapsedRow
            }
        }
        .frame(height: 54)
        .animation(.snappy(duration: 0.3), value: expanded)
    }

    private var collapsedRow: some View {
        HStack(spacing: 8) {
            tile(matchedID: "wifi", icon: net.wifiOn ? "wifi" : "wifi.slash",
                 label: "Wi-Fi", on: net.wifiOn) { toggleExpanded(.wifi) }
            tile(matchedID: "bluetooth", icon: "dot.radiowaves.right",
                 label: "Bluetooth", on: net.bluetoothOn) { toggleExpanded(.bluetooth) }
            tile(icon: appearance.isDark ? "moon.fill" : "sun.max.fill",
                 label: "Appearance", on: appearance.isDark) { Haptics.select(); appearance.toggle() }
            tile(icon: "display", label: "Displays", on: false) {
                displays.refresh(); panel = .displays
            }
        }
    }

    private func expandedRow(_ e: Expanded) -> some View {
        HStack(spacing: 8) {
            tile(matchedID: e == .wifi ? "wifi" : "bluetooth",
                 icon: tileIcon(e), label: tileLabel(e), on: tileOn(e)) { toggleExpanded(e) }
                .frame(maxWidth: .infinity)
            expandedControls(e)
                .frame(maxWidth: .infinity)
                .transition(.opacity)
        }
    }

    private func expandedControls(_ e: Expanded) -> some View {
        let on = tileOn(e)
        let enabled = (e == .wifi) ? net.wifiAvailable : net.bluetoothToggleable
        return HStack(spacing: 10) {
            Toggle("", isOn: Binding(get: { on }, set: { setPower(e, $0) }))
                .toggleStyle(.switch).labelsHidden().disabled(!enabled)
            Text(on ? "On" : "Off").font(.caption.weight(.medium)).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Button { openToggleSettings(e) } label: {
                Image(systemName: "gearshape").font(.system(size: 14)).foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(.white.opacity(0.14), in: Circle())
            }
            .buttonStyle(.plain)
            .help("\(tileLabel(e)) Settings")
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func toggleExpanded(_ e: Expanded) {
        Haptics.select()
        expanded = (expanded == e) ? nil : e
    }

    private func tileIcon(_ e: Expanded) -> String {
        e == .wifi ? (net.wifiOn ? "wifi" : "wifi.slash") : "dot.radiowaves.right"
    }
    private func tileLabel(_ e: Expanded) -> String { e == .wifi ? "Wi-Fi" : "Bluetooth" }
    private func tileOn(_ e: Expanded) -> Bool { e == .wifi ? net.wifiOn : net.bluetoothOn }
    private func setPower(_ e: Expanded, _ v: Bool) {
        if e == .wifi { net.setWiFi(v) } else { net.setBluetooth(v) }
    }
    private func openToggleSettings(_ e: Expanded) {
        if e == .wifi { net.openWiFiSettings() } else { net.openBluetoothSettings() }
    }

    private func tile(matchedID: String? = nil, icon: String, label: String, on: Bool,
                      action: @escaping () -> Void) -> some View {
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .matched(matchedID, in: tileNS)
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

/// A Control-Center-style vertical slider: a rounded bar that fills from the
/// bottom as you drag, with the level icon near the base.
struct VSlider: View {
    let value: Double
    let icon: String
    let onChange: (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let fill = min(h, max(0, h * value))
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.16))
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white).frame(height: fill)
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(value > 0.14 ? Color.black.opacity(0.55) : .white.opacity(0.85))
                    .padding(.bottom, 8)
                    .animation(.easeInOut(duration: 0.15), value: fill)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in onChange(min(1, max(0, 1 - g.location.y / h))) }
            )
        }
        .frame(maxWidth: .infinity)
    }
}

private extension View {
    /// Applies a matchedGeometryEffect only when an id is provided, so tiles
    /// that morph (Wi-Fi/Bluetooth) animate their frame while the rest don't.
    @ViewBuilder
    func matched(_ id: String?, in ns: Namespace.ID) -> some View {
        if let id { matchedGeometryEffect(id: id, in: ns) } else { self }
    }
}
