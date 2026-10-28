import AppKit
import SwiftUI

/// 无边框窗口默认 `canBecomeKey == false`，这会让里面的输入框永远拿不到键盘焦点。
/// 重写这两个属性，窗口才能真正成为 key window 并接收键盘输入。
final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// 成为 key window 时确保 App 处于激活态。
    /// 只有 App 激活，键盘事件才会被路由到本窗口，输入框才能收字。
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 不占用 Dock，只活在菜单栏 + 悬浮窗
        NSApp.setActivationPolicy(.accessory)
        makePanel()
        makeStatusItem()
    }

    // MARK: - 悬浮窗

    private func makePanel() {
        let view = NSHostingView(rootView: ContentView().environmentObject(state))
        view.frame = NSRect(x: 0, y: 0, width: 320, height: 504)

        // 不再使用 .nonactivatingPanel：那样点击不会激活 App，
        // 键盘事件会继续发给原来那个 App，输入框便无法输入。
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

        // 默认停在屏幕右下角
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            p.setFrameOrigin(NSPoint(x: f.maxX - 344, y: f.minY + 36))
        }

        p.orderFrontRegardless()
        panel = p
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
