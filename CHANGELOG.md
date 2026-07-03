# Changelog

All notable changes to ProfessorNotch are documented here.
This project follows [Semantic Versioning](https://semver.org): **MAJOR.MINOR.PATCH**.

- **PATCH** (1.0 → 1.0.1) — bug fixes only.
- **MINOR** (1.0 → 1.1) — new features, nothing broken.
- **MAJOR** (1.x → 2.0) — big redesign or a breaking change.

## [Unreleased]

_Changes that will ship in the next version go here._

## [1.0] — first public release

### Added
- **Notch control-center** hub that drops down from the MacBook notch, with six
  tabs (any except Sync can be hidden in Settings):
  - **Control** — Apple Music / Spotify controls, volume + brightness sliders,
    output-device switcher, and Wi-Fi / Bluetooth / Dark Mode / Displays toggles.
  - **Sync** — 100% local, offline, additive folder backup to an external drive
    (never deletes; optional recoverable Mirror archive).
  - **Battery**, **Apps** launcher, **Shelf + Clipboard** (with AirDrop), **System** monitor.
- Fully offline by default, no telemetry; the only optional network use is Spotify
  cover art (off until enabled).
