import AppKit
import SwiftUI
import Combine
import QuartzCore

/// 无边框窗口默认 `canBecomeKey == false`，这会让里面的输入框永远拿不到键盘焦点。
/// 重写这两个属性，窗口才能真正成为 key window 并接收键盘输入。
final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// 成为 key window 时确保 App 处于激活态。
    override func becomeKey() {
        super.becomeKey()
        if !NSApp.isActive {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// 点击窗口空白处也激活 App，避免用户以为点到了却没反应。
    override func mouseDown(with event: NSEvent) {
        if !NSApp.isActive {
            NSApp.activate(ignoringOtherApps: true)
        }
        makeKey()
        super.mouseDown(with: event)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    private var panel: PetPanel?
    private var statusItem: NSStatusItem?
    private let state = AppState()
    private var cancellables = Set<AnyCancellable>()
    private var hoverMonitor: Timer?

    /// 详情窗最后一次的位置。缩略时以它为锚点，
    /// 不依赖缩略瞬间窗口的实际 frame（可能正在动画或被内容尺寸牵动）。
    private var lastExpandedFrame: NSRect?

    private let expandedSize = NSSize(width: 320, height: 504)
    private let collapsedSize = NSSize(width: 72, height: 72)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        makePanel()
        makeStatusItem()
        observeCollapse()
        startHoverMonitor()
    }

    /// 轮询鼠标是否在窗口内。
    /// 不用 SwiftUI 的 onHover：窗口成为 key window 后退出事件可能不触发，
    /// 导致"窗口被选中时移开鼠标永远不缩略"。
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
        let view = NSHostingView(rootView: ContentView().environmentObject(state))
        view.frame = NSRect(origin: .zero, size: expandedSize)
        // 让 hosting view 跟随窗口尺寸，而不是 SwiftUI 内容反向把窗口撑/缩掉。
        // 否则内容一变（详情 → 图标）窗口会立即被拽小，且锚定在左上角、没有动画。
        view.translatesAutoresizingMaskIntoConstraints = true
        view.autoresizingMask = [.width, .height]

        // 不使用 .nonactivatingPanel：否则点击不激活 App，键盘事件发给别的 App
        let p = PetPanel(contentRect: view.frame,
                         styleMask: [.borderless],
                         backing: .buffered,
                         defer: false)
        p.contentView = view
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .floating
        p.isMovableByWindowBackground = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.becomesKeyOnlyIfNeeded = false

        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            if CommandLine.arguments.contains("--demo-top-left") {
                // 测试用：放到左上角，避开鼠标默认所在区域
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
    }

    /// 监听缩略状态，负责改窗口尺寸与位置
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
        // 展开：以当前图标位置为锚点，向左上长出去
        let base = collapsed ? (lastExpandedFrame ?? current) : current

        var frame = NSRect(x: base.maxX - size.width,
                           y: base.minY,
                           width: size.width,
                           height: size.height)

        if let screen = NSScreen.main {
            let v = screen.visibleFrame
            frame.origin.x = min(max(frame.origin.x, v.minX), v.maxX - frame.width)
            frame.origin.y = min(max(frame.origin.y, v.minY), v.maxY - frame.height)
        }

        if !collapsed { lastExpandedFrame = frame }

        animate(p, to: frame)
        // 缩略态由图标自己处理拖动，关掉背景拖动避免抢事件
        p.isMovableByWindowBackground = !collapsed
        p.invalidateShadow()
    }

    /// 显式动画，不依赖 setFrame(animate:) 的默认动画行为
    private func animate(_ window: NSWindow, to frame: NSRect) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.24
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(frame, display: true)
        }
    }

    // MARK: - NSWindowDelegate

    func windowDidMove(_ notification: Notification) {
        // 用户拖动详情窗后，记录新位置作为下次缩略的锚点
        guard let p = panel, !state.collapsed else { return }
        lastExpandedFrame = p.frame
    }

    // MARK: - 菜单栏

    private func makeStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "figure.stand",
                                     accessibilityDescription: "Ent303 Rise")
        item.button?.image?.isTemplate = true

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "显示 / 隐藏", action: #selector(togglePanel), keyEquivalent: "h"))
        menu.addItem(NSMenuItem(title: "立即提醒", action: #selector(forceReminder), keyEquivalent: "r"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q"))
        for mi in menu.items { mi.target = self }

        item.menu = menu
        statusItem = item
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
