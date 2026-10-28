import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var panel: NSPanel?
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
        view.frame = NSRect(x: 0, y: 0, width: 320, height: 464)

        let p = NSPanel(contentRect: view.frame,
                        styleMask: [.borderless, .nonactivatingPanel],
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
