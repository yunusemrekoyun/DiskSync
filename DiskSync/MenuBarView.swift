//
//  MenuBarView.swift
//  DiskSync
//
//  The MenuBarExtra popover: header + status badge, the destination drive
//  card, the sources list (with suggested quick-adds), primary actions, and
//  a footer with Settings / Open-at-login / Quit.
//

import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var app
    @State private var showSuggested = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            DriveCardView(app: app)
            sourcesSection
            actions
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 360)
        .task { await app.bootstrap() }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "externaldrive.fill.badge.timemachine")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
            Text("DiskSync")
                .font(.headline)
            Spacer()
            StatusBadge(status: app.status)
        }
    }

    // MARK: - Sources

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionLabel(title: "Sources")
                Spacer()
                Text("\(app.enabledSourceCount) of \(app.sources.count) on")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if app.sources.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(app.sources) { source in
                            SourceRowView(app: app, source: source) {
                                app.removeSource(source)
                            }
                            if source.id != app.sources.last?.id { Divider() }
                        }
                    }
                }
                .frame(maxHeight: 180)
            }

            Button {
                app.addSourcesViaPanel()
            } label: {
                Label("Add folder or file…", systemImage: "plus")
                    .font(.callout)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)

            suggestedSection
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No sources yet")
                .font(.callout.weight(.medium))
            Text("Add folders and files to start mirroring them to your drive.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private var suggestedSection: some View {
        DisclosureGroup(isExpanded: $showSuggested) {
            let present = Set(app.sources.map(\.path))
            VStack(spacing: 4) {
                ForEach(Defaults.suggested) { item in
                    let added = present.contains(item.url.path)
                    HStack {
                        Image(systemName: item.isDirectory ? "folder" : "doc")
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                        Text(item.relativePath)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button(added ? "Added" : "Add") { app.addSuggested(item) }
                            .font(.caption2)
                            .buttonStyle(.borderless)
                            .disabled(added || !FileManager.default.fileExists(atPath: item.url.path))
                    }
                }
            }
            .padding(.top, 4)
        } label: {
            Text("Suggested")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    private var actions: some View {
        HStack(spacing: 8) {
            Button {
                app.syncNow()
            } label: {
                Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!app.canSyncNow)
            .help(syncNowHelp)

            Button {
                app.openLog()
            } label: {
                Label("Open Log", systemImage: "doc.text")
            }
            .controlSize(.large)
        }
    }

    private var syncNowHelp: String {
        if !app.drive.isConnected { return "Connect the destination drive to sync." }
        if app.sources.isEmpty { return "Add at least one source first." }
        if app.isSyncing { return "A sync is already running." }
        return "Run a full reconcile now."
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            SettingsLink {
                Label("Settings", systemImage: "gearshape")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()

            Toggle("Open at login", isOn: Binding(
                get: { app.settings.runAtLogin },
                set: { app.setRunAtLogin($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .font(.caption)

            Spacer()

            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .font(.callout)
    }
}
