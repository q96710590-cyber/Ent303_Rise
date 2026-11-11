import SwiftUI
import AppKit

/// 直接播放 GIF 的视图。
///
/// SwiftUI 的 `Image` 只渲染 GIF 第一帧，而 `NSImageView` 在 `animates = true`
/// 时会按 GIF 自身的帧时长原生播放，且保留透明通道。
struct AnimatedGIFView: NSViewRepresentable {

    let url: URL?

    func makeNSView(context: Context) -> NSImageView {
        let v = NSImageView()
        v.imageScaling = .scaleProportionallyUpOrDown
        v.animates = true
        // 默认会按图片原始尺寸撑开，忽略 SwiftUI 给的 frame
        v.setContentHuggingPriority(.defaultLow, for: .horizontal)
        v.setContentHuggingPriority(.defaultLow, for: .vertical)
        v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        v.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return v
    }

    /// 让 SwiftUI 的尺寸提议决定视图大小，而不是图片的固有尺寸
    func sizeThatFits(_ proposal: ProposedViewSize,
                      nsView: NSImageView,
                      context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 288, height: proposal.height ?? 400)
    }

    func updateNSView(_ view: NSImageView, context: Context) {
        guard let url, let image = NSImage(contentsOf: url) else { return }
        if view.image !== image {
            view.image = image
        }
        view.animates = true
    }
}
