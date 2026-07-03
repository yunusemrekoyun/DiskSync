# ProfessorNotch

A native macOS **notch control-center** that turns the MacBook notch into a small,
glanceable hub — with a **100% local, offline folder-backup engine** at its core.
Hover the notch and it drops down like Dynamic Island; drag a file onto it to stash
or AirDrop it.

> Swift 6 · SwiftUI + AppKit · macOS 14+ (Apple Silicon) · **no third-party dependencies**

---

## Features

Six tabs live in the notch (all optional — toggle any off in Settings):

- **💾 Sync** — one-way, additive folder mirroring to an external drive. Never deletes
  (optional *Mirror mode* moves removed files to a recoverable on-drive archive). Live
  status, free-space bar, and an **iCloud Drive activity** line.
- **🎛 Control** — a mini Control-Center: Apple Music / Spotify controls with real album
  art (click the artwork to jump to the app), vertical **volume + brightness** sliders,
  an **output-device switcher** (CoreAudio), and four quick toggles — **Wi-Fi**,
  **Bluetooth**, **Dark Mode**, and a **Displays** panel (per-screen brightness, resolution).
- **🔋 Battery** — a live charge ring (color-coded), health, cycle count, time
  remaining, and a **charging animation** when you plug in.
- **🚀 Apps** — pinned shortcuts + **frequent** and **recent** apps (one-click launch).
- **📥 Shelf + 📋 Clipboard** — drag files onto the notch to stash/drag-out (⌘-drop to
  AirDrop), plus clipboard history (password-manager secrets are ignored).
- **📊 System** — live CPU / memory / disk / network meters.

**Privacy & footprint:** everything runs on-device. The backup engine and system
readouts make **no network calls**; the only optional network use is downloading
Spotify cover art (toggleable in Settings). No telemetry, no analytics.

---

## Install

### Download (recommended once notarized)
Grab the latest `ProfessorNotch.app` from the [Releases](../../releases) page and drag
it to **Applications**.

> **Until the app is notarized,** macOS will warn that it's from an unidentified
> developer on first launch. To allow it: open **System Settings → Privacy & Security**,
> scroll down, and click **“Open Anyway”** next to ProfessorNotch. (Advanced: you can
> also run `xattr -dr com.apple.quarantine /Applications/ProfessorNotch.app`.)

### Build from source
```bash
git clone https://github.com/yunusemrekoyun/ProfessorNotch.git
cd ProfessorNotch
open DiskSync.xcodeproj
```
In Xcode: select your team under **Signing & Capabilities**, then **⌘R**. The app is a
menu-bar/notch agent — it has no Dock icon; look for it in the notch.

---

## Permissions

ProfessorNotch is **non-sandboxed** (a power-user utility) and asks only for what it uses:

- **Full Disk Access** — to back up protected folders (Documents/Downloads/…) and to
  read iCloud sync status. *System Settings → Privacy & Security → Full Disk Access → +
  → ProfessorNotch.*
- **Automation** — to read/control Music & Spotify for the Now Playing tab (prompted on
  first use). *System Settings → Privacy & Security → Automation.*

No network entitlement is required; the app works fully offline.

---

## First-run setup (backup)

1. Open the notch → **⚙️ → Settings → Backup → Choose / Verify Destination…** and pick a
   folder on your external drive. ProfessorNotch writes a small `.disksync-target`
   marker there and **refuses to write anywhere without it**.
2. **Settings → Folders** → add the files/folders to mirror (or use the suggested
   quick-adds). Nothing is synced until you add something.
3. It syncs automatically (FSEvents + a periodic timer + on drive mount/wake), or press
   **Sync Now**. Files land at `/Volumes/<Drive>/<dest>/<your home structure>`.

Deleting a file on the Mac never deletes it on the drive (additive). Turn on **Mirror
mode** to relocate removed files into the on-drive archive instead — restore any of them
from **Settings → Archive**.

---

## How it works

- **Notch HUD** — a borderless non-activating `NSPanel` that grows from the notch with a
  spring; a small always-present drag destination over the notch catches file drops.
- **Sync engine** — a native `FileManager`-based actor: serialized runs, coalesced
  FSEvents, targeted incremental copies, atomic replace, symlink-aware, exFAT-tolerant,
  aborts safely if the drive vanishes mid-run.
- **Storage** — system SQLite (`import SQLite3`) at
  `~/Library/Application Support/DiskSync/` for settings/sources/excludes/history/archive,
  plus a rolling `sync.log`. A JSON manifest on the drive lets it "remember" its setup.
- **Battery/Audio/System** — read from the values macOS already maintains (IOKit power
  sources, CoreAudio, mach `host_statistics`); event-driven, sampled only while visible.

---

## Requirements

macOS 14+ on Apple Silicon. Best on a MacBook with a notch; on other displays the HUD
appears centered at the top of the screen.

## Roadmap

- Signed + **notarized** builds (Developer ID) for warning-free downloads.
- **Homebrew Cask** for one-command install.

## Author & Support

Made with ♥ by **Yunus Emre Koyun** — [yunusemrekoyun.com](https://www.yunusemrekoyun.com)

If ProfessorNotch is useful to you, please **⭐ star the repo** — it genuinely helps
and is the easiest way to support the project. Found a bug or have an idea? Open an
[issue](https://github.com/yunusemrekoyun/ProfessorNotch/issues).

## License

[MIT](LICENSE).
