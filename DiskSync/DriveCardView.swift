//
//  DriveCardView.swift
//  DiskSync
//
//  The centerpiece of the popover: "is my backup target there?". Shows the
//  drive, connection state, free space, last-sync time, and morphs into a
//  progress bar while a sync is running.
//

import SwiftUI

struct DriveCardView: View {
    let app: AppState

    private var connected: Bool { app.drive.isConnected }
    private var syncing: Bool { app.isSyncing }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: connected ? "externaldrive.fill" : "externaldrive")
                    .font(.title2)
                    .foregroundStyle(connected ? Color.accentColor : .secondary)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(driveName)
                            .font(.headline)
                        Circle()
                            .fill(connected ? .green : .secondary)
                            .frame(width: 7, height: 7)
                        Text(connected ? "Connected" : "Disconnected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(app.settings.destinationPath)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
            }

            if syncing, let progress = app.progress {
                VStack(alignment: .leading, spacing: 4) {
                    if progress.filesTotalEstimate > 0 {
                        ProgressView(value: progress.fraction)
                            .progressViewStyle(.linear)
                        Text("\(progress.filesProcessed.formatted()) / \(progress.filesTotalEstimate.formatted()) files")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                            .progressViewStyle(.linear)
                        Text("Copying \(progress.filesProcessed.formatted()) file(s)…")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if connected {
                FreeSpaceBar(drive: app.drive)
                if let last = app.lastSyncDate {
                    Text("Last sync \(AppState.relative(last))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Plug in the drive to resume syncing.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.25), value: connected)
        .animation(.easeInOut(duration: 0.25), value: syncing)
    }

    private var driveName: String {
        if connected, !app.drive.volumeName.isEmpty { return app.drive.volumeName }
        // Fall back to the volume component of the configured path.
        let comps = app.settings.destinationPath.split(separator: "/")
        if let idx = comps.firstIndex(of: "Volumes"), comps.count > idx + 1 {
            return String(comps[idx + 1])
        }
        return "Destination"
    }

    private var cardBackground: AnyShapeStyle {
        connected ? AnyShapeStyle(.background.secondary) : AnyShapeStyle(Color.gray.opacity(0.12))
    }
}
