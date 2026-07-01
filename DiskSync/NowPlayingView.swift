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
    @State private var media = MediaController()
    @State private var audio = AudioManager()
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
                try? await Task.sleep(for: .seconds(1.5))
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
            VStack(alignment: .leading, spacing: 3) {
                Text(media.title).font(.headline).lineLimit(1)
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
            } else if let icon = media.artworkIcon {
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
            Button {
                audio.refresh()
                showAudio = true
            } label: {
                Image(systemName: "hifispeaker.and.appletv")
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .help("Output device")

            Image(systemName: "speaker.fill").foregroundStyle(.secondary).font(.caption)
            Slider(value: Binding(get: { media.volume }, set: { media.setVolume($0) }), in: 0...1)
            Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary).font(.caption)
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

            HStack(spacing: 10) {
                Image(systemName: "speaker.fill").foregroundStyle(.secondary).font(.caption)
                Slider(value: Binding(get: { media.volume }, set: { media.setVolume($0) }), in: 0...1)
                Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary).font(.caption)
            }

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

    private static func time(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
