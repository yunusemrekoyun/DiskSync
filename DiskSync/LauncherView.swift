//
//  LauncherView.swift
//  DiskSync
//
//  The Apps tab: pinned shortcuts, frequently-used apps (frecency), and
//  recently-opened apps. Click to launch; pinned apps have a context menu.
//

import SwiftUI

struct LauncherView: View {
    @State private var store = LauncherStore.shared

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
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
                    hint("Add your favorite apps with +.")
                } else {
                    appRow(store.pinned, removable: true)
                }

                section("Frequent", store.frequentSuggestions,
                        empty: "Apps you use most will show here.")

                section("Recent", store.recentSuggestions,
                        empty: "Recently opened apps will show here.")
            }
            .padding(14)
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ apps: [LauncherApp], empty: String) -> some View {
        Divider().opacity(0.2)
        SectionLabel(title: title)
        if apps.isEmpty {
            hint(empty)
        } else {
            appRow(Array(apps.prefix(8)), removable: false)
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.caption).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
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
            Image(nsImage: store.icon(for: app.path))
                .resizable()
                .frame(width: 40, height: 40)
            Text(app.name)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .frame(width: 58)
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
