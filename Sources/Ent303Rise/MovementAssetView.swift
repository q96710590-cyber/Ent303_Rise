import SwiftUI
import AppKit

/// Keep the same NSImage across pose updates so GIF playback does not restart each frame.
struct MovementAssetView: NSViewRepresentable {
    let name: String
    let playing: Bool
    final class Coordinator { var loadedName: String? }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }

    func updateNSView(_ view: NSImageView, context: Context) {
        if context.coordinator.loadedName != name {
            if let url = Bundle.main.url(forResource: name, withExtension: "gif", subdirectory: "movement") {
                view.image = NSImage(contentsOf: url)
            }
            context.coordinator.loadedName = name
        }
        view.animates = playing
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSImageView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 150, height: proposal.height ?? 145)
    }
}
