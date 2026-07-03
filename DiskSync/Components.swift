//
//  Components.swift
//  DiskSync
//
//  Small reusable SwiftUI building blocks: status badge, free-space bar,
//  byte formatting helpers and the event-type chip.
//

import SwiftUI

// MARK: - Formatting helpers

nonisolated enum Format {
    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    /// Binary (1024-based) units for RAM, so 16 GiB reads as "16 GB" like
    /// "About This Mac" rather than "17 GB" from decimal formatting.
    static func memory(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .memory)
    }

    static func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f.string(from: date)
    }

    static func dayTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }
}

// MARK: - Status badge

struct StatusBadge: View {
    let status: SyncStatus
    var animating: Bool { if case .syncing = status { return true } else { return false } }

    private var color: Color {
        switch status {
        case .idle:    return .green
        case .syncing: return .blue
        case .paused:  return .orange
        case .error:   return .red
        }
    }

    private var title: String {
        switch status {
        case .idle:    return "Synced"
        case .syncing: return "Syncing…"
        case .paused:  return "Paused"
        case .error:   return "Error"
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .opacity(animating ? 0.4 : 1)
                .animation(animating ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true) : .default,
                           value: animating)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(color.opacity(0.14), in: Capsule())
    }
}

// MARK: - Free-space bar

struct FreeSpaceBar: View {
    let drive: DriveInfo

    private var usedFraction: Double {
        guard drive.totalBytes > 0 else { return 0 }
        return min(1, Double(drive.usedBytes) / Double(drive.totalBytes))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(usedFraction > 0.9 ? Color.red : Color.accentColor)
                        .frame(width: max(2, geo.size.width * usedFraction))
                }
            }
            .frame(height: 6)

            if drive.totalBytes > 0 {
                Text("\(Format.bytes(drive.usedBytes)) used · \(Format.bytes(drive.freeBytes)) free")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Event-type chip

struct EventTypeChip: View {
    let type: SyncEventType

    private var color: Color {
        switch type {
        case .copied:   return .green
        case .updated:  return .blue
        case .skipped:  return .gray
        case .conflict: return .orange
        case .error:    return .red
        }
    }

    private var symbol: String {
        switch type {
        case .copied:   return "plus.circle.fill"
        case .updated:  return "arrow.up.circle.fill"
        case .skipped:  return "minus.circle"
        case .conflict: return "exclamationmark.triangle.fill"
        case .error:    return "xmark.octagon.fill"
        }
    }

    var body: some View {
        Label(type.rawValue.capitalized, systemImage: symbol)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }
}

// MARK: - Section header

struct SectionLabel: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .kerning(0.5)
    }
}
