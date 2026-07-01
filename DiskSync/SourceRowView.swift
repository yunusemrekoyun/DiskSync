//
//  SourceRowView.swift
//  DiskSync
//
//  One row in the sources list: file/folder glyph, name, a subtitle with
//  item count / size, an enable toggle and a remove (–) button.
//

import SwiftUI

struct SourceRowView: View {
    let app: AppState
    let source: Source
    var onRemove: () -> Void

    @State private var subtitle: String = "…"

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: source.isDirectory ? "folder.fill" : "doc.fill")
                .foregroundStyle(source.isDirectory ? Color.accentColor : Color.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(source.displayName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { source.enabled },
                set: { app.toggleSource(source, enabled: $0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .help(source.enabled ? "Syncing enabled" : "Paused (kept in list)")

            Button(action: onRemove) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove from sync")
        }
        .padding(.vertical, 4)
        .opacity(source.enabled ? 1 : 0.55)
        .task(id: source.path) { await loadSubtitle() }
    }

    private func loadSubtitle() async {
        subtitle = "…"   // avoid showing the previous source's size while recomputing
        let path = source.path
        let isDir = source.isDirectory
        let text = await Task.detached(priority: .utility) {
            Self.describe(path: path, isDirectory: isDir)
        }.value
        subtitle = text
    }

    /// Compute a folder's item count + size, or a file's size. Bounded so very
    /// large trees don't stall (caps the walk).
    nonisolated static func describe(path: String, isDirectory: Bool) -> String {
        let fm = FileManager.default
        if !isDirectory {
            let size = ((try? fm.attributesOfItem(atPath: path))?[.size] as? Int64) ?? 0
            return Format.bytes(size)
        }
        guard let enumerator = fm.enumerator(at: URL(fileURLWithPath: path),
                                             includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                                             options: [.skipsHiddenFiles]) else {
            return "Folder"
        }
        var count = 0
        var bytes: Int64 = 0
        let cap = 50_000
        while let url = enumerator.nextObject() as? URL {
            let rv = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if rv?.isRegularFile == true {
                count += 1
                bytes += Int64(rv?.fileSize ?? 0)
            }
            if count >= cap { return "\(cap)+ items · \(Format.bytes(bytes))" }
        }
        return "\(count) item\(count == 1 ? "" : "s") · \(Format.bytes(bytes))"
    }
}
