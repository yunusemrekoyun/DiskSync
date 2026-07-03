//
//  NotchShell.swift
//  ProfessorNotch
//
//  The Dynamic-Island-style shell: a black rounded panel that grows out of the
//  notch with a spring when expanded, shrinks to a slim sideways pill for a
//  live activity (now playing / timer) or a transient flash (charge, volume,
//  download), and back to exactly the notch size when idle. Hosts HubView when
//  expanded.
//

import SwiftUI

/// Geometry handed from the AppKit controller to SwiftUI.
struct NotchGeometry: Equatable {
    var panelWidth: CGFloat
    var panelHeight: CGFloat
    var notchWidth: CGFloat
    var notchHeight: CGFloat
}

/// A transient notice the notch flashes (charge / volume / download), overriding
/// any persistent activity for a couple of seconds.
nonisolated enum FlashKind: Sendable, Equatable {
    case charging, charged, pluggedNotCharging, unplugged
    case volume, download, timerDone
}

nonisolated struct NotchFlash: Equatable, Sendable {
    var kind: FlashKind
    var level: Int = 0      // charge % or volume %
    var text: String = ""   // e.g. a downloaded file name
}

/// A persistent live activity shown in the collapsed notch as a slim pill.
nonisolated enum LiveActivityKind: Sendable, Equatable {
    case nowPlaying, timer
}

@MainActor
@Observable
final class NotchViewModel {
    var isExpanded = false
    /// Selected tab — kept here (not in HubView's @State) so it survives the
    /// panel collapsing/reopening, e.g. mid file-drag.
    var tab: HubTab = .nowPlaying
    /// A brief notice (charge/volume/download) — overrides `activity` while set.
    var flash: NotchFlash?
    /// A persistent live activity (now playing / running timer) shown collapsed.
    var activity: LiveActivityKind?
}

struct NotchShell: View {
    let app: AppState
    let model: NotchViewModel
    let geometry: NotchGeometry

    var body: some View {
        let isFull = model.isExpanded
        let isFlash = model.flash != nil && !isFull
        let isActivity = model.activity != nil && !isFull && !isFlash
        let slim = isFlash || isActivity
        let expanded = isFull || slim

        // Full panel = rounded card; slim pill = a wide bar that only grows
        // sideways (stays at notch height); idle = notch size.
        let bottomRadius: CGFloat = isFull ? 26 : (slim ? 16 : 10)
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: bottomRadius,
            bottomTrailingRadius: bottomRadius,
            topTrailingRadius: 0,
            style: .continuous
        )

        // Flashes get a wider bar (they carry a label); activities are slimmer.
        let flashWidth = min(geometry.panelWidth, geometry.notchWidth + 200)
        let activityWidth = min(geometry.panelWidth, geometry.notchWidth + 132)
        let slimWidth = isFlash ? flashWidth : activityWidth
        let slimHeight = geometry.notchHeight + 6

        let width = isFull ? geometry.panelWidth : (slim ? slimWidth : geometry.notchWidth)
        let height = isFull ? geometry.panelHeight : (slim ? slimHeight : geometry.notchHeight)
        // One combined state drives the geometry so a single spring runs.
        let sizeState = isFull ? 2 : (slim ? 1 : 0)

        return ZStack(alignment: .top) {
            shape.fill(.black)
            if isFull {
                HubView(model: model, topInset: geometry.notchHeight, notchGap: geometry.notchWidth)
                    .environment(app)
            } else if isFlash, let flash = model.flash {
                FlashView(flash: flash, notchWidth: geometry.notchWidth)
            } else if isActivity, let activity = model.activity {
                NotchActivityView(kind: activity, notchWidth: geometry.notchWidth)
            }
        }
        .frame(width: width, height: height)
        .clipShape(shape)
        .overlay { shape.strokeBorder(.white.opacity(0.08), lineWidth: 1) }
        // Pin to top-center within the fixed window so growth hangs downward.
        .frame(width: geometry.panelWidth, height: geometry.panelHeight, alignment: .top)
        .shadow(color: .black.opacity(expanded ? 0.35 : 0), radius: 16, x: 0, y: 6)
        .animation(.spring(response: 0.40, dampingFraction: 0.85), value: sizeState)
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Flash (transient notice)

/// Slim notice to the sides of the notch: a colored icon + label on the left and
/// a value (charge/volume %) or file name on the right.
struct FlashView: View {
    let flash: NotchFlash
    let notchWidth: CGFloat

    private var tint: Color {
        switch flash.kind {
        case .charging, .charged:   return .green
        case .pluggedNotCharging:   return .yellow
        case .unplugged:            return .orange
        case .volume:               return .white
        case .download:             return .blue
        case .timerDone:            return .green
        }
    }

    private var symbol: String {
        switch flash.kind {
        case .charging:           return "bolt.fill"
        case .charged:            return "bolt.badge.checkmark.fill"
        case .pluggedNotCharging: return "powerplug.fill"
        case .unplugged:          return "bolt.slash.fill"
        case .volume:             return volumeSymbol
        case .download:           return "arrow.down.circle.fill"
        case .timerDone:          return "timer"
        }
    }

    private var volumeSymbol: String {
        if flash.level <= 0 { return "speaker.slash.fill" }
        if flash.level < 34 { return "speaker.wave.1.fill" }
        if flash.level < 67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    private var label: String {
        switch flash.kind {
        case .charging:           return "Charging"
        case .charged:            return "Charged"
        case .pluggedNotCharging: return "Plugged In"
        case .unplugged:          return "On Battery"
        case .volume:             return "Volume"
        case .download:           return "Downloaded"
        case .timerDone:          return "Time's Up"
        }
    }

    private var rightText: String {
        switch flash.kind {
        case .download:  return flash.text
        case .timerDone: return ""
        default:         return "\(flash.level)%"
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(tint)
                    .symbolEffect(.pulse, isActive: flash.kind == .charging)
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)

            Spacer().frame(width: notchWidth)

            Text(rightText)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity)
        .background(tint.opacity(0.16))
        .animation(.easeInOut(duration: 0.25), value: flash)
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Live activity (persistent)

struct NotchActivityView: View {
    let kind: LiveActivityKind
    let notchWidth: CGFloat

    var body: some View {
        switch kind {
        case .nowPlaying: NowPlayingActivity(notchWidth: notchWidth)
        case .timer:      TimerActivity(notchWidth: notchWidth)
        }
    }
}

/// Album art hugging the left of the notch, an animated equalizer on the right.
struct NowPlayingActivity: View {
    @State private var media = MediaController.shared
    let notchWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            art
                .frame(maxWidth: .infinity, alignment: .trailing)
            Spacer().frame(width: notchWidth)
            Equalizer(active: media.isPlaying)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .frame(maxHeight: .infinity)
    }

    private var art: some View {
        Group {
            if let image = media.artwork ?? media.appIcon {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "music.note").font(.system(size: 9)).foregroundStyle(.white)
                }
            }
        }
        .frame(width: 20, height: 20)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

/// A small bouncing 3-bar equalizer (flat when paused).
struct Equalizer: View {
    let active: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 18.0, paused: !active)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2.5) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule()
                        .fill(.white.opacity(0.9))
                        .frame(width: 2.5, height: barHeight(t, i))
                }
            }
            .frame(height: 16, alignment: .center)
        }
    }

    private func barHeight(_ t: Double, _ i: Int) -> CGFloat {
        guard active else { return 3 }
        let phase = Double(i) * 1.15
        return 3 + 11 * (0.5 + 0.5 * sin(t * 6.5 + phase))
    }
}

/// A depleting ring on the left of the notch and the remaining time on the right.
struct TimerActivity: View {
    @State private var timer = TimerManager.shared
    let notchWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                Circle().stroke(.white.opacity(0.25), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: timer.fraction)
                    .stroke(timer.isPaused ? Color.yellow : Color.green,
                            style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: timer.isPaused ? "pause.fill" : "timer")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .frame(width: 16, height: 16)
            .frame(maxWidth: .infinity, alignment: .trailing)

            Spacer().frame(width: notchWidth)

            Text(timer.displayString)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .frame(maxHeight: .infinity)
    }
}

#Preview("Expanded") {
    let model = NotchViewModel()
    model.isExpanded = true
    return NotchShell(
        app: AppState(),
        model: model,
        geometry: NotchGeometry(panelWidth: 420, panelHeight: 250, notchWidth: 180, notchHeight: 32)
    )
    .frame(width: 480, height: 320)
    .padding()
    .background(LinearGradient(colors: [.blue, .purple], startPoint: .top, endPoint: .bottom))
}
