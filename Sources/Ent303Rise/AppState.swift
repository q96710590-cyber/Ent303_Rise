import Foundation
import Combine

/// 应用的全部状态：用户是"在电脑前"还是"去活动了"，以及累计工作时长。
///
/// MVP 阶段这里刻意用**手动切换**代替自动检测——先验证计时与提醒链路，
/// 之后再接入 `CGEventSource` 做真正的空闲检测。
final class AppState: ObservableObject {

    enum Mode {
        case working
        case away
    }

    /// 当前模式。默认是"去活动"，避免一启动就开始计时。
    @Published var mode: Mode = .away

    /// 本轮连续工作累计秒数。
    @Published var workSeconds: Int = 0

    /// 非 nil 表示正在弹出提醒。
    @Published var reminder: Suggestion?

    /// 提醒间隔（分钟）。留出可调区间方便测试。
    @Published var intervalMinutes: Int = 45

    private var timer: Timer?

    init() {
        startHeartbeat()
    }

    private func startHeartbeat() {
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        // .common 保证拖动窗口等交互时计时不中断
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        guard mode == .working, reminder == nil else { return }
        workSeconds += 1
        if workSeconds >= max(1, intervalMinutes) * 60 {
            triggerReminder()
        }
    }

    // MARK: - 用户操作

    /// 用户确认"我在电脑前"。
    func setWorking() {
        mode = .working
        reminder = nil
    }

    /// 用户确认"我离开/去活动了"，本轮计时清零。
    func setAway() {
        mode = .away
        workSeconds = 0
        reminder = nil
    }

    /// 触发一条建议。
    func triggerReminder() {
        reminder = Suggestions.random(excluding: reminder?.title)
    }

    /// 用户点了"我起来了"：关闭提醒并重新计时。
    func acknowledgeReminder() {
        reminder = nil
        workSeconds = 0
    }

    // MARK: - 派生值

    /// 距离下次提醒的进度（0...1）。
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
}
