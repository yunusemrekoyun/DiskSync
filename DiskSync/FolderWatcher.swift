//
//  FolderWatcher.swift
//  DiskSync
//
//  Thin FSEvents wrapper that watches a set of source paths for file-level
//  changes and reports the affected paths after a short debounce so rapid
//  bursts coalesce into a single sync request.
//

import Foundation
import CoreServices

/// Watches a fixed set of paths. Recreate the watcher when the source list
/// changes. All mutable state is confined to `queue`, hence @unchecked Sendable.
nonisolated final class FolderWatcher: @unchecked Sendable {
    private let paths: [String]
    private let latency: TimeInterval
    private let debounce: TimeInterval
    private let onChange: @Sendable (Set<String>) -> Void

    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "com.yunusemre.DiskSync.fsevents")
    private var pending = Set<String>()
    private var debounceItem: DispatchWorkItem?

    init(paths: [String],
         latency: TimeInterval = 1.0,
         debounce: TimeInterval = 1.5,
         onChange: @escaping @Sendable (Set<String>) -> Void) {
        self.paths = paths
        self.latency = latency
        self.debounce = debounce
        self.onChange = onChange
    }

    func start() {
        guard stream == nil, !paths.isEmpty else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let flags = UInt32(kFSEventStreamCreateFlagUseCFTypes |
                           kFSEventStreamCreateFlagFileEvents |
                           kFSEventStreamCreateFlagNoDefer)

        let callback: FSEventStreamCallback = { _, info, count, eventPaths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            let cfPaths = unsafeBitCast(eventPaths, to: NSArray.self)
            let strings = (cfPaths as? [String]) ?? []
            watcher.ingest(strings, count: count)
        }

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        ) else { return }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    func stop() {
        // Cancel any pending debounce so a torn-down watcher can't fire late.
        queue.sync {
            debounceItem?.cancel()
            debounceItem = nil
            pending.removeAll()
        }
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit { stop() }

    /// Called on `queue` from the C callback. Accumulate and debounce.
    private func ingest(_ changed: [String], count: Int) {
        for path in changed { pending.insert(path) }

        debounceItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let batch = self.pending
            self.pending.removeAll()
            guard !batch.isEmpty else { return }
            self.onChange(batch)
        }
        debounceItem = item
        queue.asyncAfter(deadline: .now() + debounce, execute: item)
    }
}
