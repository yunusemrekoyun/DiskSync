//
//  HubView.swift
//  DiskSync
//
//  The SwiftUI content hosted inside the notch HUD panel. Three tabs:
//  Now Playing (media + audio), Sync (DiskSync), and Apps (launcher).
//
//  Phase 1: tab shell + the Sync tab wired to existing UI; the other tabs are
//  placeholders we'll fill in next.
//

import SwiftUI

enum HubTab: String, CaseIterable, Identifiable {
    case nowPlaying, sync, apps
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .nowPlaying: return "play.circle.fill"
        case .sync:       return "externaldrive.fill"
        case .apps:       return "square.grid.2x2.fill"
        }
    }

    var title: String {
        switch self {
        case .nowPlaying: return "Now Playing"
        case .sync:       return "Sync"
        case .apps:       return "Apps"
        }
    }
}

struct HubView: View {
    @Environment(AppState.self) private var app
    @State private var tab: HubTab = .nowPlaying

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
        HStack(spacing: 4) {
            ForEach(HubTab.allCases) { item in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { tab = item }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: item.symbol)
                        if tab == item {
                            Text(item.title).font(.caption.weight(.semibold))
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .foregroundStyle(tab == item ? .white : .secondary)
                    .background {
                        if tab == item {
                            Capsule().fill(.clear)
                                .glassEffect(.regular.interactive(), in: .capsule)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer()
            // Sync status dot mirrors the engine state.
            StatusBadge(status: app.status)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .nowPlaying:
            NowPlayingView()
        case .sync:
            syncTab
        case .apps:
            LauncherView()
        }
    }

    private var syncTab: some View {
        VStack(spacing: 10) {
            DriveCardView(app: app)
            HStack {
                Button {
                    app.syncNow()
                } label: {
                    Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .disabled(!app.canSyncNow)

                SettingsLink {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.glass)
            }
        }
        .padding(12)
    }

}
