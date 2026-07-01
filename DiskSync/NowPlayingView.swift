//
//  NowPlayingView.swift
//  DiskSync
//
//  The Now Playing tab: artwork, track info, transport controls, and a system
//  volume slider. A speaker button flips to an audio panel for switching the
//  output device (CoreAudio). Polls only while visible.
//

import SwiftUI

struct NowPlayingView: View {
    @State private var media = MediaController.shared
    @State private var audio = AudioManager.shared
    @State private var showAudio = false

    var body: some View {
        ZStack {
            if showAudio {
                audioPanel.transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                mainPanel.transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .padding(14)
        .animation(.snappy(duration: 0.25), value: showAudio)
        .task {
            while !Task.isCancelled {
                await media.refresh()
                // Poll quickly while something is playing, slowly when idle
                // (also eases repeated AppleScript when permission is denied).
                try? await Task.sleep(for: media.hasTrack ? .seconds(1.5) : .seconds(5))
            }
        }
    }

    // MARK: - Main (track + transport)

    private var mainPanel: some View {
        VStack(spacing: 12) {
            if media.hasTrack { trackView } else { emptyView }
            Divider().opacity(0.2)
            volumeRow
        }
    }

    private var trackView: some View {
        HStack(spacing: 12) {
            artwork
                .onTapGesture { openSource() }
                .help("Open in \(media.source.displayName)")
            VStack(alignment: .leading, spacing: 3) {
                Text(media.title).font(.headline).lineLimit(1)
                    .contentShape(Rectangle())
                    .onTapGesture { openSource() }
                    .help("Open in \(media.source.displayName)")
                Text(media.artist.isEmpty ? media.source.displayName : media.artist)
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                progressRow
                HStack(spacing: 18) {
                    controlButton("backward.fill") { await media.previous() }
                    controlButton(media.isPlaying ? "pause.fill" : "play.fill", size: 26) { await media.playPause() }
                    controlButton("forward.fill") { await media.next() }
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
    }

    private var artwork: some View {
        Group {
            if let art = media.artwork {
                Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
            } else if let icon = media.appIcon {
                Image(nsImage: icon).resizable()
            } else {
                ZStack {
                    LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "music.note").font(.title).foregroundStyle(.white.opacity(0.9))
                }
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
        .onHover { inside in
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }

    private var progressRow: some View {
        VStack(spacing: 2) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.18))
                    Capsule().fill(.white).frame(width: max(2, geo.size.width * media.fraction))
                }
            }
            .frame(height: 4)
            HStack {
                Text(Self.time(media.position)).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text(Self.time(media.duration)).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.top, 4)
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note.list").font(.system(size: 30)).foregroundStyle(.secondary)
            Text("Nothing playing").font(.headline)
            Text("Play something in Apple Music or Spotify.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var volumeRow: some View {
        HStack(spacing: 10) {
            VolumeSlider(value: media.volume) { media.setVolume($0) }
            Button {
                audio.refresh()
                showAudio = true
            } label: {
                Image(systemName: "hifispeaker.and.appletv")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Output device")
        }
    }

    // MARK: - Audio (output device picker)

    private var audioPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    showAudio = false
                } label: {
                    Label("Back", systemImage: "chevron.left").labelStyle(.titleAndIcon)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                Spacer()
                Text("Output").font(.headline)
                Spacer()
                Spacer().frame(width: 44)   // balance the back button
            }

            VolumeSlider(value: media.volume) { media.setVolume($0) }

            Divider().opacity(0.2)

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(audio.outputs) { device in
                        Button {
                            audio.select(device)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: audio.symbol(for: device))
                                    .frame(width: 22)
                                    .foregroundStyle(device.id == audio.currentID ? Color.accentColor : .secondary)
                                Text(device.name)
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Spacer()
                                if device.id == audio.currentID {
                                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                                }
                            }
                            .padding(.vertical, 5)
                            .padding(.horizontal, 8)
                            .background(device.id == audio.currentID ? AnyShapeStyle(.white.opacity(0.08)) : AnyShapeStyle(.clear),
                                        in: RoundedRectangle(cornerRadius: 8))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 130)
        }
    }

    // MARK: - Helpers

    private func controlButton(_ symbol: String, size: CGFloat = 18, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: size))
                .foregroundStyle(.white)
                .frame(width: size + 12, height: size + 12)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func openSource() {
        guard media.hasTrack else { return }
        Haptics.select()
        media.openSourceApp()
    }

    private static func time(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Control-Center-style volume bar: a chunky rounded capsule that fills as you
/// drag anywhere on it, with a level-aware speaker glyph inside.
struct VolumeSlider: View {
    let value: Double
    let onChange: (Double) -> Void

    private var icon: String {
        if value <= 0.001 { return "speaker.slash.fill" }
        if value < 0.34 { return "speaker.wave.1.fill" }
        if value < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let fill = min(width, max(0, width * value))
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.16))
                Capsule().fill(.white).frame(width: fill)
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    // Dark glyph once the white fill reaches it, light otherwise.
                    .foregroundStyle(value > 0.14 ? Color.black.opacity(0.6) : Color.white.opacity(0.8))
                    .padding(.leading, 11)
                    .animation(.easeInOut(duration: 0.15), value: fill)
            }
            .frame(height: 28)
            .clipShape(Capsule())
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in onChange(min(1, max(0, g.location.x / width))) }
            )
        }
        .frame(height: 28)
    }
}
