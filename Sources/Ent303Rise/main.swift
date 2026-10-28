import AppKit
import SwiftUI
import Combine
import QuartzCore

/// 无边框窗口默认 `canBecomeKey == false`，这会让里面的输入框永远拿不到键盘焦点。
final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func becomeKey() {
        super.becomeKey()
        if !NSApp.isActive {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    override func mouseDown(with event: NSEvent) {
        if !NSApp.isActive {
            NSApp.activate(ignoringOtherApps: true)
        }
        makeKey()
        super.mouseDown(with: event)
    }
}

/// 缩略态图标。
/// 用 AppKit 而非 SwiftUI 手势：未激活窗口的第一次点击默认只用于激活，
/// 会被系统吞掉，导致"拖不动图标"。`acceptsFirstMouse` 返回 true 可以拿到第一下。
final class IconView: NSView {

    var image: NSImage? {
        didSet { needsDisplay = true }
    }
    var onClick: (() -> Void)?

    private var dragStartMouse: NSPoint = .zero
    private var dragStartOrigin: NSPoint = .zero
    private var didDrag = false

    /// 图标绘制边长（固定，不随窗口动画放大缩小）
    private let iconSide: CGFloat = 64
    /// 超过这个位移就算拖动，否则算点击
    private let dragThreshold: CGFloat = 3

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()
        guard let image else { return }
        let side = min(iconSide, min(bounds.width, bounds.height))
        let rect = NSRect(x: (bounds.width - side) / 2,
                          y: (bounds.height - side) / 2,
                          width: side,
                          height: side)
        image.draw(in: rect)
    }

    override func mouseDown(with event: NSEvent) {
        didDrag = false
        dragStartMouse = NSEvent.mouseLocation
        dragStartOrigin = window?.frame.origin ?? .zero
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let now = NSEvent.mouseLocation
        let dx = now.x - dragStartMouse.x
        let dy = now.y - dragStartMouse.y
        if abs(dx) > dragThreshold || abs(dy) > dragThreshold {
            didDrag = true
        }
        window.setFrameOrigin(NSPoint(x: dragStartOrigin.x + dx,
                                      y: dragStartOrigin.y + dy))
    }

    override func mouseUp(with event: NSEvent) {
        if !didDrag {
            onClick?()
        }
        didDrag = false
    }
}

/// 详情界面的 hosting view。
/// 默认 `acceptsFirstMouse` 为 false：窗口未激活时的第一下点击只用于激活，
/// 不会落到按钮上，用户会觉得"点了一下没反应"。
final class FirstMouseHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    private var panel: PetPanel?
    private var hostingView: NSHostingView<AnyView>?
    private var iconView: IconView?
    private var inspectorWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private let state = AppState()
    private var cancellables = Set<AnyCancellable>()
    private var hoverMonitor: Timer?

    /// 详情窗最后一次的位置。缩略时以它为锚点。
    private var lastExpandedFrame: NSRect?

    private let expandedSize = NSSize(width: 320, height: 504)
    private let collapsedSize = NSSize(width: 72, height: 72)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        makePanel()
        makeStatusItem()
        observeCollapse()
        startHoverMonitor()
        runDemoMoveIfNeeded()

        if CommandLine.arguments.contains("--open-inspector") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.toggleInspector()
            }
        }
    }

    // MARK: - 鼠标位置轮询

    /// 不用 SwiftUI 的 onHover：窗口成为 key window 后退出事件可能不触发。
    private func startHoverMonitor() {
        let t = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
            guard let self, let p = self.panel else { return }
            self.state.updateHover(inside: p.frame.contains(NSEvent.mouseLocation))
        }
        RunLoop.main.add(t, forMode: .common)
        hoverMonitor = t
    }

    // MARK: - 悬浮窗

    private func makePanel() {
        let hosting = FirstMouseHostingView(rootView: AnyView(ContentView().environmentObject(state)))
        hosting.frame = NSRect(origin: .zero, size: expandedSize)
        // 让 hosting view 跟随窗口尺寸，而不是 SwiftUI 内容反向把窗口撑/缩掉
        hosting.translatesAutoresizingMaskIntoConstraints = true
        hosting.autoresizingMask = [.width, .height]

        let icon = IconView(frame: NSRect(origin: .zero, size: expandedSize))
        icon.autoresizingMask = [.width, .height]
        icon.image = Self.loadLogo()
        icon.isHidden = true
        icon.onClick = { [weak self] in
            self?.state.expand()
        }

        let container = NSView(frame: NSRect(origin: .zero, size: expandedSize))
        container.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        container.addSubview(icon)

        let p = PetPanel(contentRect: container.frame,
                         styleMask: [.borderless],
                         backing: .buffered,
                         defer: false)
        p.contentView = container
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .floating
        p.isMovableByWindowBackground = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false

        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            if CommandLine.arguments.contains("--demo-top-left") {
                p.setFrameOrigin(NSPoint(x: f.minX + 40,
                                         y: f.maxY - expandedSize.height - 40))
            } else {
                p.setFrameOrigin(NSPoint(x: f.maxX - expandedSize.width - 24,
                                         y: f.minY + 36))
            }
        }

        p.orderFrontRegardless()
        p.delegate = self
        lastExpandedFrame = p.frame

        panel = p
        hostingView = hosting
        iconView = icon
    }

    private static func loadLogo() -> NSImage? {
        if let url = Bundle.main.url(forResource: "logo", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        return NSImage(systemSymbolName: "figure.stand", accessibilityDescription: nil)
    }

    // MARK: - 缩略 / 展开

    private func observeCollapse() {
        state.$collapsed
            .removeDuplicates()
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] collapsed in
                self?.applyCollapsed(collapsed)
            }
            .store(in: &cancellables)
    }

    private func applyCollapsed(_ collapsed: Bool) {
        guard let p = panel else { return }
        let current = p.frame
        let size = collapsed ? collapsedSize : expandedSize

        // 缩略：以详情窗最后位置为锚点，落在它右下角
        // 展开：以当前图标位置为锚点，让详情窗的右下角对着图标右下角
        let base = collapsed ? (lastExpandedFrame ?? current) : current

        var frame = NSRect(x: base.maxX - size.width,
                           y: base.minY,
                           width: size.width,
                           height: size.height)

        if let screen = NSScreen.main {
            let v = screen.visibleFrame
            // 先尽量保持锚点，放不下再贴边
            frame.origin.x = min(max(frame.origin.x, v.minX), v.maxX - frame.width)
            frame.origin.y = min(max(frame.origin.y, v.minY), v.maxY - frame.height)
        }

        if !collapsed { lastExpandedFrame = frame }

        hostingView?.isHidden = collapsed
        iconView?.isHidden = !collapsed

        animate(p, to: frame)
        p.isMovableByWindowBackground = !collapsed
        p.invalidateShadow()
    }

    private func animate(_ window: NSWindow, to frame: NSRect) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.24
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(frame, display: true)
        }
    }

    // MARK: - NSWindowDelegate

    func windowDidMove(_ notification: Notification) {
        guard let p = panel, !state.collapsed else { return }
        lastExpandedFrame = p.frame
    }

    // MARK: - 调试

    private func runDemoMoveIfNeeded() {
        guard CommandLine.arguments.contains("--demo-move") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            self?.state.collapseToIcon()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            guard let p = self?.panel else { return }
            p.setFrameOrigin(NSPoint(x: 400, y: 300))
            Debug.log("moved icon to \(p.frame)")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            self?.state.expand()
        }
    }

    // MARK: - 菜单栏

    private func makeStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "figure.stand",
                                     accessibilityDescription: "Ent303 Rise")
        item.button?.image?.isTemplate = true

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "检查台", action: #selector(toggleInspector), keyEquivalent: "i"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "显示 / 隐藏", action: #selector(togglePanel), keyEquivalent: "h"))
        menu.addItem(NSMenuItem(title: "立即提醒", action: #selector(forceReminder), keyEquivalent: "r"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q"))
        for mi in menu.items { mi.target = self }

        item.menu = menu
        statusItem = item
    }

    // MARK: - 检查台

    @objc private func toggleInspector() {
        if inspectorWindow == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 760),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            w.title = "Ent303 检查台"
            w.isReleasedWhenClosed = false
            w.contentViewController = NSHostingController(
                rootView: InspectorView().environmentObject(state)
            )
            w.delegate = self
            w.center()
            inspectorWindow = w
        }
        guard let w = inspectorWindow else { return }

        if w.isVisible {
            w.orderOut(nil)
            state.setInspectorOpen(false)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            w.makeKeyAndOrderFront(nil)
            state.setInspectorOpen(true)
        }
    }

    func windowWillClose(_ notification: Notification) {
        if let w = notification.object as? NSWindow, w === inspectorWindow {
            state.setInspectorOpen(false)
        }
    }

    @objc private func togglePanel() {
        guard let p = panel else { return }
        if p.isVisible {
            p.orderOut(nil)
        } else {
            p.orderFrontRegardless()
        }
    }

    @objc private func forceReminder() {
        state.triggerReminder()
        panel?.orderFrontRegardless()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
