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
@MainActor
@Observable
final class NotchViewModel {
    var isExpanded = false
}

struct NotchShell: View {
    let app: AppState
    let model: NotchViewModel
    let geometry: NotchGeometry

    var body: some View {
        let expanded = model.isExpanded
        // Square top corners so the panel hangs flush from the top edge (like
        // the notch / Dynamic Island); only the bottom corners are rounded.
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: expanded ? 26 : 10,
            bottomTrailingRadius: expanded ? 26 : 10,
            topTrailingRadius: 0,
            style: .continuous
        )

        let width = expanded ? geometry.panelWidth : geometry.notchWidth
        let height = expanded ? geometry.panelHeight : geometry.notchHeight

        return ZStack(alignment: .top) {
            shape.fill(.black)
            if expanded {
                HubView()
                    .environment(app)
                    .opacity(expanded ? 1 : 0)
            }
        }
        .frame(width: width, height: height)
        .clipShape(shape)
        .overlay { shape.strokeBorder(.white.opacity(0.08), lineWidth: 1) }
        // Pin to top-center within the fixed window so growth hangs downward.
        .frame(width: geometry.panelWidth, height: geometry.panelHeight, alignment: .top)
        .shadow(color: .black.opacity(expanded ? 0.35 : 0), radius: 16, x: 0, y: 6)
        .animation(.spring(response: 0.40, dampingFraction: 0.86), value: expanded)
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
