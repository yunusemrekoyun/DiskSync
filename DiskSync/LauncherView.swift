//
//  LauncherView.swift
//  DiskSync
//
//  The Apps tab: a row of pinned shortcuts and a row of recently-opened apps.
//  Click to launch; pinned apps can be removed via the context menu.
//

import SwiftUI

struct LauncherView: View {
    @State private var store = LauncherStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Pinned shortcuts
            HStack {
                SectionLabel(title: "Shortcuts")
                Spacer()
                Button {
                    store.addPinnedViaPanel()
                } label: {
                    Image(systemName: "plus.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Add a shortcut")
            }

            if store.pinned.isEmpty {
                Text("Add your favorite apps with +.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                appRow(store.pinned, removable: true)
            }

            Divider().opacity(0.2)

            // Recently opened
            SectionLabel(title: "Recent")
            if store.recentSuggestions.isEmpty {
                Text("Recently opened apps will appear here.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                appRow(Array(store.recentSuggestions.prefix(8)), removable: false)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
    }

    private func appRow(_ apps: [LauncherApp], removable: Bool) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(apps) { app in
                    tile(app, removable: removable)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func tile(_ app: LauncherApp, removable: Bool) -> some View {
        VStack(spacing: 4) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                .resizable()
                .frame(width: 42, height: 42)
            Text(app.name)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .frame(width: 60)
        }
        .contentShape(Rectangle())
        .onTapGesture { store.launch(app) }
        .contextMenu {
            Button("Open") { store.launch(app) }
            if removable {
                Button("Remove", role: .destructive) { store.removePinned(app) }
            } else {
                Button("Pin to Shortcuts") { store.addPinned(URL(fileURLWithPath: app.path)) }
            }
        }
    }
}
