import AppKit
import SwiftUI

/// 盖在平台上的透明手柄：按住它拖动 = 移动整个无边框窗口。
/// 用 AppKit 的 performDrag 走系统原生拖拽，手感和普通窗口一致。
struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DraggingView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DraggingView: NSView {
        override var acceptsFirstResponder: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}
