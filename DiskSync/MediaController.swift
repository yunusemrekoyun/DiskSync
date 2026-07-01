//
//  MediaController.swift
//  DiskSync
//
//  Reads and controls the currently-playing track in Apple Music / Spotify via
//  AppleScript, and exposes the system output volume. 100% local — no network.
//  Polled only while the notch is open (see NowPlayingView) to save resources.
//

import Foundation
import AppKit

nonisolated enum MediaSource: String, Sendable {
    case none, music, spotify

    var appName: String? {
        switch self {
        case .music:   return "Music"
        case .spotify: return "Spotify"
        case .none:    return nil
        }
    }

    var displayName: String {
        switch self {
        case .music:   return "Apple Music"
        case .spotify: return "Spotify"
        case .none:    return "Nothing playing"
        }
    }

    var bundleID: String? {
        switch self {
        case .music:   return "com.apple.Music"
        case .spotify: return "com.spotify.client"
        case .none:    return nil
        }
    }
}

@MainActor
@Observable
final class MediaController {
    var source: MediaSource = .none
    var title = ""
    var artist = ""
    var album = ""
    var isPlaying = false
    var position: Double = 0      // seconds
    var duration: Double = 0      // seconds
    var volume: Double = 0.5      // 0…1
    var artworkURL: String = ""
    var artwork: NSImage?         // real cover art (fetched), nil ⇒ fall back to icon

    private var lastArtKey = ""

    var hasTrack: Bool { source != .none && !title.isEmpty }

    var fraction: Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, position / duration))
    }

    /// The Music/Spotify app icon, used as artwork (album art needs network for
    /// Spotify, which we avoid; this stays fully offline).
    var artworkIcon: NSImage? {
        guard let bundleID = source.bundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    // MARK: - Polling

    func refresh() async {
        if let raw = await Self.runScript(Self.stateScript), raw != "none" {
            parse(raw)
        } else {
            source = .none; title = ""; artist = ""; album = ""; isPlaying = false
            position = 0; duration = 0; artworkURL = ""; artwork = nil; lastArtKey = ""
        }
        await refreshVolume()
        await refreshArtwork()
    }

    private func parse(_ raw: String) {
        let f = raw.components(separatedBy: "|")
        guard f.count >= 7 else { source = .none; title = ""; return }
        source = (f[0] == "Spotify") ? .spotify : (f[0] == "Music" ? .music : .none)
        isPlaying = f[1].contains("playing")
        title = f[2]; artist = f[3]; album = f[4]
        // AppleScript returns numbers in the system locale (e.g. "76,71" in TR);
        // normalize the decimal separator before parsing.
        position = Double(f[5].replacingOccurrences(of: ",", with: ".")) ?? 0
        duration = Double(f[6].replacingOccurrences(of: ",", with: ".")) ?? 0
        artworkURL = f.count >= 8 ? f[7] : ""
    }

    // MARK: - Artwork

    /// Fetches the real cover art once per track. Spotify exposes an https URL
    /// (downloaded here); Apple Music exposes local artwork data (no network).
    private func refreshArtwork() async {
        let key = source == .music ? "music:\(title)|\(artist)" : artworkURL
        guard key != lastArtKey else { return }
        lastArtKey = key

        if artworkURL.hasPrefix("http"), let url = URL(string: artworkURL),
           let data = await Self.downloadData(url) {
            artwork = NSImage(data: data)
            return
        }
        if source == .music, let data = await Self.musicArtworkData() {
            artwork = NSImage(data: data)
            return
        }
        artwork = nil
    }

    private nonisolated static func downloadData(_ url: URL) async -> Data? {
        (try? await URLSession.shared.data(from: url))?.0
    }

    /// Apple Music's locally-stored artwork bytes (offline).
    private nonisolated static func musicArtworkData() async -> Data? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var error: NSDictionary?
                let script = NSAppleScript(source: "tell application \"Music\" to get data of artwork 1 of current track")
                let descriptor = script?.executeAndReturnError(&error)
                let data = descriptor?.data
                continuation.resume(returning: (data?.isEmpty == false) ? data : nil)
            }
        }
    }

    // MARK: - Controls

    func playPause() async { await control("playpause") }
    func next() async { await control("next track") }
    func previous() async { await control("previous track") }

    private func control(_ command: String) async {
        guard let app = source.appName else { return }
        _ = await Self.runScript("tell application \"\(app)\" to \(command)")
        await refresh()
    }

    // MARK: - Volume

    func refreshVolume() async {
        if let raw = await Self.runScript("output volume of (get volume settings)"),
           let v = Double(raw) {
            volume = v / 100
        }
    }

    func setVolume(_ value: Double) {
        volume = value
        let level = Int((value * 100).rounded())
        Task { _ = await Self.runScript("set volume output volume \(level)") }
    }

    // MARK: - AppleScript

    /// Runs an AppleScript off the main thread and returns its string result.
    private nonisolated static func runScript(_ source: String) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var error: NSDictionary?
                let script = NSAppleScript(source: source)
                let result = script?.executeAndReturnError(&error)
                continuation.resume(returning: result?.stringValue)
            }
        }
    }

    /// Picks whichever player is playing (else running) and returns a
    /// pipe-delimited snapshot, or "none".
    private nonisolated static let stateScript = """
    set out to "none"
    tell application "System Events"
        set isSpot to (exists (processes whose name is "Spotify"))
        set isMusic to (exists (processes whose name is "Music"))
    end tell
    set pref to ""
    if isSpot then
        try
            tell application "Spotify"
                if player state is playing then set pref to "Spotify"
            end tell
        end try
    end if
    if pref is "" and isMusic then
        try
            tell application "Music"
                if player state is playing then set pref to "Music"
            end tell
        end try
    end if
    if pref is "" then
        if isSpot then
            set pref to "Spotify"
        else if isMusic then
            set pref to "Music"
        end if
    end if
    if pref is "Spotify" then
        try
            tell application "Spotify"
                set theState to (player state as text)
                set theName to (name of current track)
                set theArtist to (artist of current track)
                set theAlbum to (album of current track)
                set thePos to (player position)
                set theDur to ((duration of current track) / 1000)
                set theArt to ""
                try
                    set theArt to (artwork url of current track)
                end try
                set out to "Spotify|" & theState & "|" & theName & "|" & theArtist & "|" & theAlbum & "|" & thePos & "|" & theDur & "|" & theArt
            end tell
        end try
    else if pref is "Music" then
        try
            tell application "Music"
                set theState to (player state as text)
                set theName to (name of current track)
                set theArtist to (artist of current track)
                set theAlbum to (album of current track)
                set thePos to (player position)
                set theDur to (duration of current track)
                set out to "Music|" & theState & "|" & theName & "|" & theArtist & "|" & theAlbum & "|" & thePos & "|" & theDur & "|"
            end tell
        end try
    end if
    return out
    """
}
