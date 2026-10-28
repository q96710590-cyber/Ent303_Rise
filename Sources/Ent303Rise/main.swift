import AppKit
import SwiftUI
import Combine

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

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var panel: PetPanel?
    private var statusItem: NSStatusItem?
    private let state = AppState()
    private var cancellables = Set<AnyCancellable>()

    private let expandedSize = NSSize(width: 320, height: 504)
    private let collapsedSize = NSSize(width: 72, height: 72)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        makePanel()
        makeStatusItem()
        observeCollapse()
    }

    // MARK: - 悬浮窗

    private func makePanel() {
        let view = NSHostingView(rootView: ContentView().environmentObject(state))
        view.frame = NSRect(origin: .zero, size: expandedSize)

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
            p.setFrameOrigin(NSPoint(x: f.maxX - expandedSize.width - 24,
                                     y: f.minY + 36))
        }

        p.orderFrontRegardless()
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

        // 统一以「当前窗口右下角」为锚点：
        // 缩略时图标落在详情窗右下；展开时以图标右下角向左上长出去。
        var frame = NSRect(x: current.maxX - size.width,
                           y: current.minY,
                           width: size.width,
                           height: size.height)

        if let screen = NSScreen.main {
            let v = screen.visibleFrame
            frame.origin.x = min(max(frame.origin.x, v.minX), v.maxX - frame.width)
            frame.origin.y = min(max(frame.origin.y, v.minY), v.maxY - frame.height)
        }

        p.setFrame(frame, display: true, animate: true)
        // 缩略态由图标自己处理拖动，关掉背景拖动避免抢事件
        p.isMovableByWindowBackground = !collapsed
        p.invalidateShadow()
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
