# DiskSync

A complete, **100% local & offline** native macOS menu-bar app that continuously
mirrors a set of user-chosen folders and files to an external drive — one-way and
additive, like iCloud but entirely on-device.

- **No networking.** No `URLSession`, no `Network.framework`, no network entitlement.
- **No third-party dependencies.** Only Apple system frameworks + the system
  `SQLite3` library (`import SQLite3`).
- **No shelling out.** The sync engine is implemented natively with `FileManager`.
- **All state on-device.** SQLite + a rolling text log under
  `~/Library/Application Support/DiskSync/`.

---

## What it does

- **One-way, additive.** Copies new/changed items from each source → destination,
  mirroring your home-directory structure. It **never deletes** on the drive. If the
  destination file is newer, the Mac still wins (source-of-truth) and the run records
  a *conflict* event — no data is ever lost because nothing is removed.
- **Continuous & automatic.** Watches sources via **FSEvents** (file-level, ~1.5 s
  debounce) and syncs affected paths. Also reconciles on drive mount, on a periodic
  timer (default 15 min), and on wake-from-sleep.
- **Sources vs Excludes** are separate concepts:
  - **Sources** — your explicit list (starts empty). Add files *and* folders in one
    multi-select pass. Each row has a toggle (pause without removing) and a remove (–).
  - **Excludes** — name/glob patterns skipped *inside* synced folders (seeded with
    `node_modules` and `.DS_Store`). Directory matches skip the whole subtree.

---

## Project structure

```
DiskSync/
├─ DiskSync.xcodeproj
├─ Info.plist                 ← LSUIElement = true, bundle keys
├─ DiskSync.entitlements      ← non-sandboxed (app-sandbox = false)
├─ README.md
└─ DiskSync/                  ← all sources (file-system-synchronized group)
   ├─ DiskSyncApp.swift       @main · MenuBarExtra + Settings scenes
   ├─ AppState.swift          @MainActor @Observable coordinator
   ├─ Models.swift            value types + SyncStatus
   ├─ Database.swift          SQLite3 wrapper (actor) + migrations
   ├─ ConfigStore.swift       settings/sources/excludes + bookmark resolve
   ├─ SyncManager.swift       native engine (actor) + lock + queue + progress
   ├─ FolderWatcher.swift     FSEvents wrapper
   ├─ VolumeMonitor.swift     mount/unmount/wake + marker + capacity
   ├─ LoginItem.swift         SMAppService (open at login)
   ├─ Notifier.swift          UserNotifications
   ├─ Logger.swift            rolling text log + app paths
   ├─ Components.swift        StatusBadge, FreeSpaceBar, chips, formatting
   ├─ DriveCardView.swift     destination drive card / progress
   ├─ SourceRowView.swift     one source row (icon, size, toggle, remove)
   ├─ MenuBarView.swift       the popover
   ├─ SettingsView.swift      General / Folders / Excludes / About tabs
   └─ ActivityView.swift      activity & history feed
```

The data store is a single SQLite DB at
`~/Library/Application Support/DiskSync/disksync.sqlite`; the text log is `sync.log`
in the same folder.

---

## Build & run

Requirements: macOS 14+ (Apple Silicon), Xcode 16+.

### One-time Xcode settings

The Swift sources build as-is. Two project settings must be set in Xcode for the app
to behave as a non-sandboxed, menu-bar-only agent (these can't be scripted safely while
Xcode is open). Select the **DiskSync** target → **Build Settings** and set:

| Setting | Value |
| --- | --- |
| Generate Info.plist File | **No** |
| Info.plist File | **Info.plist** |
| Code Signing Entitlements | **DiskSync.entitlements** |
| Enable App Sandbox | **No** |
| Swift Language Version | **6** (recommended) |
| macOS Deployment Target | **14.0** (optional) |

Then open **Signing & Capabilities** and, if an **App Sandbox** capability is listed,
click the **×** to remove it (so the app can read arbitrary folders and write to
`/Volumes/…`). Leave **Hardened Runtime** on.

> Sandboxed alternative (not the default): keep App Sandbox on, add
> `com.apple.security.files.user-selected.read-write` to the entitlements, and rely on
> the security-scoped bookmarks the app already creates for every source and the
> destination.

Build & run with ⌘R. The app has **no Dock icon**; look for the drive glyph in the
menu bar.

---

## First-run setup

1. Click the menu-bar icon to open the popover.
2. **Choose the destination:** Settings → General → *Choose / Verify Destination…*
   Pick a folder on your external drive (e.g. `/Volumes/MetalMini/PC-Sync`). DiskSync
   writes a small `.disksync-target` marker there and **refuses to write anywhere
   without it.**
3. **Add sources:** *Add folder or file…* (multi-select files and folders), or use the
   **Suggested** quick-adds (`Works`, `Downloads`, `.zprofile`, `.config`, `.ssh`, …).
   Nothing is added automatically.
4. Press **Sync Now**, or just let it run — edits sync within ~1–2 s, and a full
   reconcile runs on mount / timer / wake.

Files land at `/Volumes/<Drive>/<dest>/<same structure as your home>`. Deleting a file
on the Mac never deletes it on the drive.

---

## Grant Full Disk Access (for protected folders)

Because the app is non-sandboxed, it can read most locations directly. macOS still
protects a few folders (Desktop, Documents, Downloads). To mirror those without prompts:

**System Settings → Privacy & Security → Full Disk Access → +** → add **DiskSync.app**,
then toggle it on and relaunch the app.

---

## Open at login

Toggle **Open at login** in the popover footer or in Settings → General. This uses
`SMAppService.mainApp.register()` / `.unregister()`; the switch reflects the real
registration state. (Run the app from `/Applications` for the most reliable behavior.)

---

## Notifications

On first launch the app requests notification permission. When enabled, you get a local
summary on completion (e.g. *"Synced 124 files to MetalMini"*) and on errors. Toggle in
Settings → General.

---

## Behavior & edge cases

- **Drive not mounted** → status shows **Paused**; syncs are skipped and retried on the
  next mount. Unplug/replug and sleep/wake are handled without errors.
- **Disk full / write error / busy file** → logged to `sync.log` + `sync_events`, the
  run continues, and you’re notified.
- **Symlinks** are recreated as links (never followed). **exFAT/FAT** destinations only
  get mtime preserved; owner/permission errors are ignored.
- **Overlapping runs are prevented** (the engine serializes and coalesces rapid
  FSEvents; latest request wins).
- All configuration persists across relaunch in SQLite; open-at-login reflects reality.
