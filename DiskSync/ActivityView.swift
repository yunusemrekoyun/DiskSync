//
//  ActivityView.swift
//  DiskSync
//
//  The Activity / History tab: a feed of recent per-file events plus a
//  summary of recent runs. This is where the native engine's per-file
//  tracking shines.
//

import SwiftUI

struct ActivityView: View {
    let app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !app.recentRuns.isEmpty {
                runsSummary
                Divider()
            }
            eventsFeed
        }
    }

    private var runsSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(title: "Recent Runs")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(app.recentRuns.prefix(12)) { run in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(Format.dayTime(run.startedAt))
                                .font(.caption2.weight(.semibold))
                            Text("\(run.filesCopied) files · \(Format.bytes(run.bytesCopied))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            if run.errorsCount > 0 {
                                Text("\(run.errorsCount) error(s)")
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                            } else {
                                Text("OK")
                                    .font(.caption2)
                                    .foregroundStyle(.green)
                            }
                        }
                        .padding(8)
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(12)
    }

    private var eventsFeed: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(title: "Activity")
                .padding(.horizontal, 12)
                .padding(.top, 12)

            if app.recentEvents.isEmpty {
                Text("No activity yet. Run a sync to see file-level events here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(app.recentEvents) { event in
                    HStack(spacing: 10) {
                        EventTypeChip(type: event.type)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(event.relativePath)
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(event.message)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(Format.shortDate(event.timestamp))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .listRowSeparator(.visible)
                }
                .listStyle(.inset)
            }
        }
    }
}
