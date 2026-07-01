//
//  NotchShell.swift
//  DiskSync
//
//  The Dynamic-Island-style shell: a black rounded panel that grows out of the
//  notch with a spring when expanded, and shrinks back to exactly the notch
//  size (so it blends invisibly with the real notch) when collapsed. Hosts the
//  SwiftUI HubView and adds Liquid Glass accents.
//

import SwiftUI

/// Geometry handed from the AppKit controller to SwiftUI.
struct NotchGeometry: Equatable {
    var panelWidth: CGFloat
    var panelHeight: CGFloat
    var notchWidth: CGFloat
    var notchHeight: CGFloat
}

/// Drives the open/closed animation. Toggled by `NotchController`, observed by
/// SwiftUI so the spring runs on the main thread inside the view.
/// The kind of power event the notch is announcing.
nonisolated enum FlashKind: Sendable, Equatable {
    case charging, charged, pluggedNotCharging, unplugged
}

/// A brief power notice shown by the notch (e.g. "Charging 80%").
nonisolated struct NotchFlash: Equatable, Sendable {
    var kind: FlashKind
    var level: Int
}

@MainActor
@Observable
final class NotchViewModel {
    var isExpanded = false
    /// Selected tab — kept here (not in HubView's @State) so it survives the
    /// panel collapsing/reopening, e.g. mid file-drag.
    var tab: HubTab = .nowPlaying
    /// When set, the notch briefly drops open to show a power notice.
    var flash: NotchFlash?
}

struct NotchShell: View {
    let app: AppState
    let model: NotchViewModel
    let geometry: NotchGeometry

    var body: some View {
        let isFull = model.isExpanded
        let isFlash = model.flash != nil && !isFull
        let expanded = isFull || isFlash

        // Full panel = rounded card; charging flash = a slim wide pill that only
        // grows sideways (not down); collapsed = notch size.
        let bottomRadius: CGFloat = isFull ? 26 : (isFlash ? 16 : 10)
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: bottomRadius,
            bottomTrailingRadius: bottomRadius,
            topTrailingRadius: 0,
            style: .continuous
        )

        let flashWidth = min(geometry.panelWidth, geometry.notchWidth + 200)
        let flashHeight = geometry.notchHeight + 6      // stays at notch level

        let width = isFull ? geometry.panelWidth : (isFlash ? flashWidth : geometry.notchWidth)
        let height = isFull ? geometry.panelHeight : (isFlash ? flashHeight : geometry.notchHeight)
        // One combined state drives the geometry so a single spring runs (two
        // separate .animation(value:) modifiers would fight over the frame).
        let sizeState = isFull ? 2 : (isFlash ? 1 : 0)

        return ZStack(alignment: .top) {
            shape.fill(.black)
            if isFlash, let flash = model.flash {
                FlashView(flash: flash, notchWidth: geometry.notchWidth)
            } else if isFull {
                HubView(model: model, topInset: geometry.notchHeight, notchGap: geometry.notchWidth)
                    .environment(app)
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

/// Slim power notice shown when the charger is (un)plugged: a colored icon +
/// label to the left of the notch and the charge % to the right. Grows only
/// sideways, and its color/icon make the state obvious at a glance.
struct FlashView: View {
    let flash: NotchFlash
    let notchWidth: CGFloat

    private var tint: Color {
        switch flash.kind {
        case .charging, .charged:   return .green
        case .pluggedNotCharging:   return .yellow
        case .unplugged:            return .orange
        }
    }

    private var symbol: String {
        switch flash.kind {
        case .charging:           return "bolt.fill"
        case .charged:            return "bolt.badge.checkmark.fill"
        case .pluggedNotCharging: return "powerplug.fill"
        case .unplugged:          return "bolt.slash.fill"
        }
    }

    private var label: String {
        switch flash.kind {
        case .charging:           return "Charging"
        case .charged:            return "Charged"
        case .pluggedNotCharging: return "Plugged In"
        case .unplugged:          return "On Battery"
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

            Spacer().frame(width: notchWidth)   // reserve the physical notch

            Text("\(flash.level)%")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity)
        .background(tint.opacity(0.18))          // subtle colored glow per state
        .animation(.easeInOut(duration: 0.25), value: flash)
        .environment(\.colorScheme, .dark)
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
