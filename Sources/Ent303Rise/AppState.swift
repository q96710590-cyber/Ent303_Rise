import Foundation
import Combine
import CoreGraphics

/// 应用的全部状态。
///
/// 提供两种提醒方式：
/// 1. **自动检测**——读取系统空闲时长，自己判断你在不在电脑前
/// 2. **手动确认**——由用户点图标声明状态
///
/// 两种方式共用同一套计时与提醒逻辑。
final class AppState: ObservableObject {

    enum Mode {
        case working
        case away
    }

    enum DetectionMode: String, CaseIterable, Identifiable {
        case auto = "自动检测"
        case manual = "手动确认"
        var id: String { rawValue }
    }

    @Published var mode: Mode = .away
    @Published var workSeconds: Int = 0
    @Published var reminder: Suggestion?
    @Published var intervalMinutes: Int = 45
    @Published var detectionMode: DetectionMode = .auto

    /// 最近一次读到的系统空闲秒数（仅用于界面展示）。
    @Published var systemIdleSeconds: Double = 0

    /// 空闲不超过这个值 → 认为仍在电脑前工作
    private let activeThreshold: Double = 120
    /// 空闲超过这个值 → 认为人已经离开，本轮计时清零
    private let awayThreshold: Double = 300

    private var timer: Timer?

    init() {
        startHeartbeat()
        // 调试用：带 --demo-reminder 启动时，1 秒后自动弹一条提醒
        if CommandLine.arguments.contains("--demo-reminder") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.triggerReminder()
            }
        }
    }

    private func startHeartbeat() {
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        switch detectionMode {
        case .auto:   tickAuto()
        case .manual: tickManual()
        }
    }

    private func tickManual() {
        guard mode == .working, reminder == nil else { return }
        workSeconds += 1
        checkThreshold()
    }

    private func tickAuto() {
        let anyEvent = CGEventType(rawValue: ~0)!
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState,
                                                           eventType: anyEvent)
        systemIdleSeconds = idle

        if idle >= awayThreshold {
            // 人离开了：清零，等回来重新开始
            if mode != .away || workSeconds != 0 {
                mode = .away
                workSeconds = 0
                reminder = nil
            }
            return
        }

        if idle <= activeThreshold {
            if mode != .working { mode = .working }
            guard reminder == nil else { return }
            workSeconds += 1
            checkThreshold()
        }
        // 介于两者之间：只是短暂停顿，不计时但也不清零
    }

    private func checkThreshold() {
        if workSeconds >= max(1, intervalMinutes) * 60 {
            triggerReminder()
        }
    }

    // MARK: - 用户操作

    func setWorking() {
        mode = .working
        reminder = nil
    }

    func setAway() {
        mode = .away
        workSeconds = 0
        reminder = nil
    }

    func triggerReminder() {
        reminder = Suggestions.random(excluding: reminder?.title)
    }

    func acknowledgeReminder() {
        reminder = nil
        workSeconds = 0
    }

    // MARK: - 派生值

    var progress: Double {
        let total = Double(max(1, intervalMinutes) * 60)
        return min(1.0, Double(workSeconds) / total)
    }

    var formattedDuration: String {
        let h = workSeconds / 3600
        let m = (workSeconds % 3600) / 60
        let s = workSeconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }

    /// 距离下一次提醒还有多久。
    var remainingText: String {
        let left = max(0, max(1, intervalMinutes) * 60 - workSeconds)
        let m = left / 60
        let s = left % 60
        return m > 0 ? "\(m) 分 \(s) 秒" : "\(s) 秒"
    }

    /// 自动模式下用一句话描述当前判断结果。
    var autoStatusText: String {
        let idle = Int(systemIdleSeconds)
        if idle >= Int(awayThreshold) {
            return "检测到你已离开，计时已清零"
        }
        if idle > Int(activeThreshold) {
            return "可能暂时离开了（空闲 \(idle) 秒）"
        }
        return "正在电脑前工作（空闲 \(idle) 秒）"
    }
}
