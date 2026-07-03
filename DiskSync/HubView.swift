//
//  HubView.swift
//  ProfessorNotch
//
//  The SwiftUI content hosted inside the notch HUD panel. A tab bar that splits
//  around the physical notch, plus the six hub modules: Control (media, volume,
//  brightness, and quick toggles), Sync (the offline backup engine), Battery,
//  Apps (launcher), Shelf + Clipboard, and System monitor. Any module except
//  Sync can be hidden from Settings; hidden tabs are filtered out of the bar.
//

import SwiftUI

enum HubTab: String, CaseIterable, Identifiable {
    case nowPlaying, sync, battery, apps, shelf, system
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .nowPlaying: return "switch.2"
        case .sync:       return "externaldrive.fill"
        case .battery:    return "battery.100"      // battery uses a custom ring icon
        case .apps:       return "square.grid.2x2.fill"
        case .shelf:      return "tray.full.fill"
        case .system:     return "gauge.with.dots.needle.67percent"
        }
    }

    var title: String {
        switch self {
        case .nowPlaying: return "Control"
        case .sync:       return "Sync"
        case .battery:    return "Battery"
        case .apps:       return "Apps"
        case .shelf:      return "Shelf"
        case .system:     return "System"
        }
    }
}

struct HubView: View {
    @Environment(AppState.self) private var app
    let model: NotchViewModel
    @State private var battery = BatteryManager.shared
    @State private var prefs = Preferences.shared
    @Environment(\.openSettings) private var openSettings

    /// Height of the physical notch band; tab icons sit within it (beside the
    /// notch) and the selected title drops just below it.
    var topInset: CGFloat = 0
    /// Center gap reserved for the physical notch between the two tab groups.
    var notchGap: CGFloat = 40

    /// Tabs the user has enabled (Sync is core and always present).
    private var visibleTabs: [HubTab] {
        HubTab.allCases.filter { tab in
            switch tab {
            case .sync:       return true
            case .nowPlaying: return prefs.showNowPlaying
            case .battery:    return prefs.showBattery
            case .apps:       return prefs.showLauncher
            case .shelf:      return prefs.showShelf
            case .system:     return prefs.showSystem
            }
        }
    }

    /// The effective selected tab — falls back if the chosen one was hidden.
    private var tab: HubTab { visibleTabs.contains(model.tab) ? model.tab : (visibleTabs.first ?? .sync) }

    private var leftTabs: [HubTab] { Array(visibleTabs.prefix((visibleTabs.count + 1) / 2)) }
    private var rightTabs: [HubTab] { Array(visibleTabs.suffix(visibleTabs.count / 2)) }

    var body: some View {
        // The black shell + clipping is provided by NotchShell; this is pure content.
        VStack(spacing: 0) {
            tabBar
            Divider().opacity(0.25)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.colorScheme, .dark)
        .task { await app.bootstrap() }
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        VStack(spacing: 2) {
            // Icon row lives in the notch band: tabs split to either side of the
            // notch (the center Spacer is the notch gap), nothing behind it.
            HStack(spacing: 4) {
                ForEach(leftTabs) { tabButton($0) }
                Spacer(minLength: notchGap)
                ForEach(rightTabs) { tabButton($0) }
            }
            .frame(height: max(topInset, 34))
            // Selected tab name centered under the notch, with an always-visible
            // gear menu (Settings / Quit) pinned to the right.
            ZStack {
                Text(tab.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    settingsMenu
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    private var settingsMenu: some View {
        Menu {
            Button("Settings…") { openSettings() }
            Divider()
            Button("Quit ProfessorNotch") { NSApplication.shared.terminate(nil) }
        } label: {
            Image(systemName: "gearshape")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 20)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    @ViewBuilder
    private func tabButton(_ item: HubTab) -> some View {
        Button {
            if model.tab != item { Haptics.select() }
            withAnimation(.easeInOut(duration: 0.18)) { model.tab = item }
        } label: {
            Group {
                if item == .battery {
                    BatteryRing(level: battery.level,
                                color: Color(nsColor: battery.ringColor),
                                diameter: 22)
                } else {
                    Image(systemName: item.symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tab == item ? .white : .secondary)
                }
            }
            .frame(width: 34, height: 34)
            .background {
                if tab == item { Circle().fill(.white.opacity(0.16)) }
            }
            .contentShape(Rectangle())   // whole frame is clickable, not just the glyph
        }
        .buttonStyle(.plain)
        .help(item.title)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .nowPlaying:
            ControlView()
        case .battery:
            BatteryView()
        case .sync:
            syncTab
        case .apps:
            LauncherView()
        case .shelf:
            ShelfView()
        case .system:
            SystemMonitorView()
        }
    }

    private var syncTab: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 10) {
                HStack {
                    StatusBadge(status: app.status)
                    Spacer()
                }
                DriveCardView(app: app)
                CloudStatusRow()
                if !app.destinationConfigured {
                    // First run: no destination yet — guide the user straight to it.
                    Button {
                        app.pickDestination()
                    } label: {
                        Label("Set Up Backup…", systemImage: "externaldrive.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                } else {
                    Button {
                        app.syncNow()
                    } label: {
                        Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(!app.canSyncNow)
                    .help(app.canSyncNow
                          ? "Sync the selected folders now."
                          : (app.sources.isEmpty
                             ? "Add folders in Settings to start backing up."
                             : "Connect the backup drive to sync."))
                    if app.sources.isEmpty {
                        Button("Add folders…") { openSettings() }
                            .buttonStyle(.glass)
                            .font(.caption)
                    }
                }
            }
            .padding(12)
        }
    }

}

/// Compact iCloud Drive activity line for the Sync tab.
private struct CloudStatusRow: View {
    @State private var cloud = CloudStatus.shared

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: cloud.isActive ? "arrow.triangle.2.circlepath.icloud.fill" : "icloud")
                .foregroundStyle(cloud.isActive ? Color.blue : .secondary)
                .symbolEffect(.pulse, isActive: cloud.isActive)
            Text("iCloud").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(cloud.summary)
                .font(.caption.weight(.medium))
                .foregroundStyle(cloud.isActive ? Color.blue : .secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        .task {
            // Snapshot on open, then refresh while the Sync tab is visible.
            while !Task.isCancelled {
                await cloud.refresh()
                try? await Task.sleep(for: .seconds(8))
            }
        }
    }
}
