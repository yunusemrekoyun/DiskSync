//
//  SettingsView.swift
//  DiskSync
//
//  The Settings window, opened on demand from the popover. Organized into
//  General / Folders / Excludes / Activity / About tabs. Everything the app
//  does is configurable here and persists to SQLite.
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        TabView {
            NotchSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            GeneralSettings(app: app)
                .tabItem { Label("Backup", systemImage: "externaldrive") }
            FoldersSettings(app: app)
                .tabItem { Label("Folders", systemImage: "folder") }
            ExcludesSettings(app: app)
                .tabItem { Label("Excludes", systemImage: "nosign") }
            ArchiveSettings(app: app)
                .tabItem { Label("Archive", systemImage: "clock.arrow.circlepath") }
            ActivityView(app: app)
                .tabItem { Label("Activity", systemImage: "list.bullet.rectangle") }
            AboutSettings()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 560, height: 460)
        .onAppear { NSApplication.shared.activate(ignoringOtherApps: true) }
    }
}

// MARK: - General (app-wide notch hub preferences)

private struct NotchSettings: View {
    @State private var prefs = Preferences.shared

    var body: some View {
        Form {
            Section("Notch tabs") {
                Toggle("Now Playing", isOn: Binding(get: { prefs.showNowPlaying }, set: { prefs.showNowPlaying = $0 }))
                Toggle("Battery", isOn: Binding(get: { prefs.showBattery }, set: { prefs.showBattery = $0 }))
                Toggle("Apps (Launcher)", isOn: Binding(get: { prefs.showLauncher }, set: { prefs.showLauncher = $0 }))
                Toggle("Shelf & Clipboard", isOn: Binding(get: { prefs.showShelf }, set: { prefs.showShelf = $0 }))
                Toggle("System", isOn: Binding(get: { prefs.showSystem }, set: { prefs.showSystem = $0 }))
                Text("Sync is always shown. Hidden tabs disappear from the notch.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Feedback") {
                Toggle("Haptic feedback", isOn: Binding(get: { prefs.hapticsEnabled }, set: { prefs.hapticsEnabled = $0 }))
            }

            Section("Clipboard") {
                Toggle("Keep clipboard history", isOn: Binding(get: { prefs.clipboardEnabled }, set: { prefs.clipboardEnabled = $0 }))
                Button("Clear clipboard history") { ClipboardManager.shared.clear() }
                Text("Password managers' concealed/one-time items are never stored.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Now Playing") {
                Toggle("Download album art (network)", isOn: Binding(get: { prefs.artworkNetworkEnabled }, set: { prefs.artworkNetworkEnabled = $0 }))
                Text("When off, everything stays offline; Spotify shows the app icon instead of cover art.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    let app: AppState
    @State private var intervalText = ""

    var body: some View {
        Form {
            Section("Destination") {
                LabeledContent("Drive") {
                    HStack {
                        Circle().fill(app.drive.isConnected ? .green : .secondary).frame(width: 8, height: 8)
                        Text(app.drive.isConnected ? (app.drive.volumeName.isEmpty ? "Connected" : app.drive.volumeName) : "Disconnected")
                            .foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Path") {
                    Text(app.settings.destinationPath)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Button("Choose / Verify Destination…") { app.pickDestination() }
                Text("DiskSync writes a small marker file (\(Defaults.markerFileName)) to confirm the target. It will not write anywhere without it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Syncing") {
                Toggle("Automatic sync", isOn: Binding(
                    get: { app.settings.autoSyncEnabled },
                    set: { app.setAutoSync($0) }))
                Toggle("Notifications", isOn: Binding(
                    get: { app.settings.notificationsEnabled },
                    set: { app.setNotifications($0) }))
                Toggle("Open at login", isOn: Binding(
                    get: { app.settings.runAtLogin },
                    set: { app.setRunAtLogin($0) }))
                LabeledContent("Sync interval") {
                    HStack {
                        TextField("", text: $intervalText)
                            .frame(width: 50)
                            .multilineTextAlignment(.trailing)
                            .onSubmit { commitInterval() }
                        Text("minutes")
                            .foregroundStyle(.secondary)
                        Stepper("", value: Binding(
                            get: { app.settings.syncIntervalMinutes },
                            set: { app.setSyncInterval($0); intervalText = "\($0)" }), in: 1...1440)
                            .labelsHidden()
                    }
                }
            }

            Section("Mirror mode") {
                Toggle("Mirror deletions to the drive", isOn: Binding(
                    get: { app.settings.mirrorEnabled },
                    set: { app.setMirror($0) }))
                Text("When on, items you delete or move on this Mac are relocated into a recoverable archive on the drive (\(Defaults.archiveFolderName)) instead of staying as extra copies. Nothing is ever hard-deleted — restore anything from the Archive tab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { intervalText = "\(app.settings.syncIntervalMinutes)" }
    }

    private func commitInterval() {
        if let value = Int(intervalText) { app.setSyncInterval(value) }
        intervalText = "\(app.settings.syncIntervalMinutes)"
    }
}

// MARK: - Folders

private struct FoldersSettings: View {
    let app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Folders & Files")
                    .font(.headline)
                Spacer()
                Button {
                    app.addSourcesViaPanel()
                } label: { Label("Add…", systemImage: "plus") }
            }
            .padding()

            if app.sources.isEmpty {
                Spacer()
                Text("No sources yet — add folders or files to mirror.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                List {
                    ForEach(app.sources) { source in
                        SourceRowView(app: app, source: source) { app.removeSource(source) }
                    }
                }
                .listStyle(.inset)
            }

            Divider()
            DisclosureGroup("Suggested quick-adds") {
                let present = Set(app.sources.map(\.path))
                ForEach(Defaults.suggested) { item in
                    let added = present.contains(item.url.path)
                    let exists = FileManager.default.fileExists(atPath: item.url.path)
                    HStack {
                        Image(systemName: item.isDirectory ? "folder" : "doc").foregroundStyle(.secondary)
                        Text(item.relativePath).font(.callout)
                        Spacer()
                        Button(added ? "Added" : "Add") { app.addSuggested(item) }
                            .disabled(added || !exists)
                    }
                    .foregroundStyle(exists ? .primary : .secondary)
                }
            }
            .padding()
        }
    }
}

// MARK: - Excludes

private struct ExcludesSettings: View {
    let app: AppState
    @State private var newPattern = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                TextField("New pattern (e.g. *.tmp, .git, build/)", text: $newPattern)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                Button("Add", action: add).disabled(newPattern.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()

            List {
                ForEach(app.excludes) { rule in
                    HStack {
                        Toggle("", isOn: Binding(
                            get: { rule.enabled },
                            set: { var r = rule; r.enabled = $0; app.updateExclude(r) }))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        Text(rule.pattern)
                            .font(.body.monospaced())
                        if rule.sourceId == nil {
                            Text("global").font(.caption2).foregroundStyle(.secondary)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(.quaternary, in: Capsule())
                        }
                        Spacer()
                        Button {
                            app.removeExclude(rule)
                        } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.inset)

            Text("Matching files and folders are skipped inside synced folders. Directory matches skip the entire subtree.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding([.horizontal, .bottom])
        }
    }

    private func add() {
        app.addExclude(pattern: newPattern)
        newPattern = ""
    }
}

// MARK: - Archive (recovery)

private struct ArchiveSettings: View {
    let app: AppState
    @State private var search = ""

    private var items: [ArchivedItem] {
        guard !search.isEmpty else { return app.archivedItems }
        return app.archivedItems.filter { $0.relativePath.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "clock.arrow.circlepath").foregroundStyle(.secondary)
                Text("Archived (deleted) items")
                    .font(.headline)
                Spacer()
                if !app.archivedItems.isEmpty {
                    TextField("Search", text: $search)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                }
                if !app.drive.isConnected {
                    Label("Drive disconnected", systemImage: "externaldrive.badge.xmark")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding()

            if app.archivedItems.isEmpty {
                Spacer()
                VStack(spacing: 6) {
                    Image(systemName: "tray").font(.title).foregroundStyle(.secondary)
                    Text("Nothing archived")
                        .font(.callout.weight(.medium))
                    Text("When mirror mode is on, files you delete on this Mac are kept here and can be restored.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                }
                Spacer()
            } else {
                List {
                    ForEach(items) { item in
                        HStack(spacing: 10) {
                            Image(systemName: "doc")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.name).font(.body.weight(.medium)).lineLimit(1)
                                Text(item.relativePath)
                                    .font(.caption2).foregroundStyle(.secondary)
                                    .lineLimit(1).truncationMode(.middle)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(Format.bytes(item.bytes)).font(.caption2).foregroundStyle(.secondary)
                                Text(Format.dayTime(item.deletedAt)).font(.caption2).foregroundStyle(.secondary)
                            }
                            Button("Restore") { app.restoreArchived(item) }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .disabled(!app.drive.isConnected)
                            Button {
                                app.deleteArchivedPermanently(item)
                            } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.secondary)
                                .help("Delete permanently")
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listStyle(.inset)
            }
        }
    }
}

// MARK: - About

private struct AboutSettings: View {
    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 88, height: 88)
            Text("ProfessorNotch").font(.title2.weight(.semibold))
            Text("Version \(version)").foregroundStyle(.secondary)
            Text("A notch control-center with an offline folder-backup engine at its core.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Label("100% local — no telemetry.", systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider().padding(.vertical, 6)

            HStack(spacing: 12) {
                Link(destination: URL(string: "https://github.com/yunusemrekoyun/ProfessorNotch")!) {
                    Label("Star on GitHub", systemImage: "star.fill")
                }
                Link(destination: URL(string: "https://www.yunusemrekoyun.com")!) {
                    Label("Website", systemImage: "globe")
                }
            }
            .buttonStyle(.bordered)

            Text("Made with ♥ by Yunus Emre Koyun")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
