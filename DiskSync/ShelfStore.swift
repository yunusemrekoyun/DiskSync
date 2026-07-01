//
//  ShelfStore.swift
//  DiskSync
//
//  A temporary "shelf" you can drag files onto and drag back off — handy for
//  moving files between apps/windows. ⌘-dropping instead hands the files to
//  AirDrop. Fully local; the shelf is in-memory (transient by nature).
//

import Foundation
import AppKit

nonisolated struct ShelfItem: Identifiable, Hashable, Sendable {
    var url: URL
    var id: URL { url }
    var name: String { url.lastPathComponent }
}

@MainActor
@Observable
final class ShelfStore {
    static let shared = ShelfStore()
    private init() {}

    var items: [ShelfItem] = []
    private var iconCache: [String: NSImage] = [:]

    func add(_ urls: [URL]) {
        for url in urls where !items.contains(where: { $0.url == url }) {
            items.append(ShelfItem(url: url))
        }
    }

    func remove(_ item: ShelfItem) { items.removeAll { $0.id == item.id } }
    func clear() { items.removeAll() }

    func icon(for url: URL) -> NSImage {
        if let cached = iconCache[url.path] { return cached }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        iconCache[url.path] = image
        return image
    }

    /// Hand the files to AirDrop. macOS shows the recipient picker (there is no
    /// public API for a fully silent send).
    func airDrop(_ urls: [URL]) {
        guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else { return }
        NSApp.activate(ignoringOtherApps: true)
        service.perform(withItems: urls)
    }
}
