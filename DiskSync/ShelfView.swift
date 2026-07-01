//
//  ShelfView.swift
//  DiskSync
//
//  Combined tab: a file "shelf" (drag files in to stash, drag back out to move;
//  ⌘-drop to AirDrop) on top, and clipboard history below (click to re-copy).
//

import SwiftUI
import UniformTypeIdentifiers

struct ShelfView: View {
    @State private var shelf = ShelfStore.shared
    @State private var clip = ClipboardManager.shared
    @State private var dropTargeted = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                shelfSection
                Divider().opacity(0.2)
                clipboardSection
            }
            .padding(14)
        }
    }

    // MARK: - Shelf

    private var shelfSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionLabel(title: "Shelf")
                Spacer()
                if !shelf.items.isEmpty {
                    Button("Clear") { shelf.clear() }
                        .font(.caption2).buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }

            dropZone
        }
    }

    private var dropZone: some View {
        Group {
            if shelf.items.isEmpty {
                VStack(spacing: 4) {
                    Image(systemName: "arrow.down.doc").font(.title2).foregroundStyle(.secondary)
                    Text("Drag files here").font(.caption).foregroundStyle(.secondary)
                    Text("⌘-drag to AirDrop").font(.caption2).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(shelf.items) { item in shelfTile(item) }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(dropTargeted ? 0.12 : 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                .foregroundStyle(dropTargeted ? Color.accentColor : .white.opacity(0.15))
        )
        .dropDestination(for: URL.self) { urls, _ in
            // ⌘ held at drop → AirDrop; otherwise stash on the shelf.
            if NSEvent.modifierFlags.contains(.command) {
                shelf.airDrop(urls)
            } else {
                shelf.add(urls)
            }
            Haptics.action()   // confirming tick on drop
            return true
        } isTargeted: { dropTargeted = $0 }
    }

    private func shelfTile(_ item: ShelfItem) -> some View {
        VStack(spacing: 4) {
            Image(nsImage: shelf.icon(for: item.url))
                .resizable().frame(width: 38, height: 38)
            Text(item.name)
                .font(.caption2).foregroundStyle(.white.opacity(0.9))
                .lineLimit(1).frame(width: 56)
        }
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .contextMenu {
            Button("AirDrop") { shelf.airDrop([item.url]) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
            Button("Remove", role: .destructive) { shelf.remove(item) }
        }
    }

    // MARK: - Clipboard

    private var clipboardSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionLabel(title: "Clipboard")
                Spacer()
                if !clip.items.isEmpty {
                    Button("Clear") { clip.clear() }
                        .font(.caption2).buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }

            if clip.items.isEmpty {
                Text("Copied text and images will appear here.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 4) {
                    ForEach(clip.items) { item in clipRow(item) }
                }
            }
        }
    }

    private func clipRow(_ item: ClipItem) -> some View {
        Button {
            clip.copyToPasteboard(item)
        } label: {
            HStack(spacing: 8) {
                if item.kind == .image, let data = item.imageData, let img = NSImage(data: data) {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                    Text("Image").font(.caption).foregroundStyle(.secondary)
                } else {
                    Image(systemName: "doc.on.clipboard").font(.caption).foregroundStyle(.secondary).frame(width: 28)
                    Text(item.text ?? "")
                        .font(.caption).foregroundStyle(.white)
                        .lineLimit(1).truncationMode(.tail)
                }
                Spacer()
                Image(systemName: "arrow.up.doc.on.clipboard").font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Copy") { clip.copyToPasteboard(item) }
            Button("Remove", role: .destructive) { clip.remove(item) }
        }
    }
}
