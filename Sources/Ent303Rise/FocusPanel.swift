import SwiftUI

/// 耳机按钮打开的 Focus 面板：三种提醒模式用 Tab 切换。
struct FocusPanel: View {
    @EnvironmentObject var state: AppState
    @Binding var tab: Int

    private let brown = Color(red: 0.36, green: 0.31, blue: 0.30)
    private let cream = Color(red: 1.0, green: 0.97, blue: 0.85)
    private let yellow = Color(red: 1.0, green: 0.81, blue: 0.39)

    private let tabs = ["Focus", "番茄钟"]

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(0..<tabs.count, id: \.self) { i in
                    Button { tab = i } label: {
                        Text(tabs[i])
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(i == tab ? yellow : Color.white.opacity(0.45)))
                            .foregroundStyle(brown.opacity(i == tab ? 1 : 0.6))
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }

            Group {
                switch tab {
                case 0: focusTab
                default: pomodoroTab
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(cream))
    }

    // MARK: Focus（提醒间隔 → 模式 → 提醒设置）
    private var focusTab: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $state.acceptReminder) {
                Text("接受提醒").font(.system(size: 10, weight: .semibold)).foregroundStyle(brown)
            }
            .toggleStyle(.switch).controlSize(.mini)

            Divider().opacity(0.35)

            HStack {
                Text("提醒间隔").font(.system(size: 10)).foregroundStyle(brown.opacity(0.6))
                Spacer()
                Text("\(state.intervalSeconds / 60) 分钟")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(brown)
                Stepper("", value: Binding(
                    get: { max(1, state.intervalSeconds / 60) },
                    set: { state.intervalSeconds = $0 * 60 }
                ), in: 1...120).labelsHidden()
            }
            Text("推荐 \(AppState.bestIntervalMinutes) 分钟（研究建议的最短提醒间隔）")
                .font(.system(size: 9)).foregroundStyle(brown.opacity(0.5))

            Divider().opacity(0.35)

            // 自动 / 手动
            HStack(spacing: 6) {
                modeChip("自动检测", active: state.detectionMode == .auto) { state.detectionMode = .auto }
                modeChip("手动", active: state.detectionMode == .manual) { state.detectionMode = .manual }
            }
            if state.detectionMode == .auto {
                Toggle(isOn: $state.adaptive) {
                    Text("自适应").font(.system(size: 10)).foregroundStyle(brown)
                }
                .toggleStyle(.switch).controlSize(.mini)
                Text("初期间隔更长，用得越久越接近推荐值")
                    .font(.system(size: 9))
                    .foregroundStyle(brown.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if state.detectionMode == .manual {
                HStack(spacing: 6) {
                    stateChip("在电脑前", active: state.mode == .working) { state.setWorking() }
                    stateChip("去活动", active: state.mode == .away) { state.setAway() }
                }
            }

            Divider().opacity(0.35)

            Toggle(isOn: $state.useCustomWindow) {
                Text("仅限时段").font(.system(size: 10)).foregroundStyle(brown)
            }
            .toggleStyle(.switch).controlSize(.mini)

            if state.useCustomWindow {
                HStack(spacing: 6) {
                    Text("从").font(.system(size: 9)).foregroundStyle(brown.opacity(0.6))
                    Stepper(String(format: "%02d:00", state.windowStartHour), value: $state.windowStartHour, in: 0...23)
                        .font(.system(size: 9)).controlSize(.mini)
                    Text("到").font(.system(size: 9)).foregroundStyle(brown.opacity(0.6))
                    Stepper(String(format: "%02d:00", state.windowEndHour), value: $state.windowEndHour, in: 1...24)
                        .font(.system(size: 9)).controlSize(.mini)
                }
            }
        }
    }

    private func modeChip(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(Capsule().fill(active ? yellow : Color.white.opacity(0.5)))
                .foregroundStyle(brown.opacity(active ? 1 : 0.6))
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
    }

    /// 手动模式的状态按钮：圆角矩形 + 绿色，与上面的胶囊按钮区分
    private func stateChip(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        let green = Color(red: 0.81, green: 0.85, blue: 0.45)
        return Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(active ? green : Color.white.opacity(0.55))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(brown.opacity(0.35), lineWidth: 1)
                )
                .foregroundStyle(brown.opacity(active ? 1 : 0.65))
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: 番茄钟
    private var pomodoroTab: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("时长").font(.system(size: 10)).foregroundStyle(brown.opacity(0.6))
                Spacer()
                Text("\(state.pomodoroMinutes) 分钟")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(brown)
                Stepper("", value: $state.pomodoroMinutes, in: 5...90).labelsHidden()
            }

            Text("剩余 " + String(format: "%02d:%02d",
                                   state.pomodoroRemaining / 60,
                                   state.pomodoroRemaining % 60))
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(brown)
                .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: 6) {
                Button {
                    if state.pomodoroRemaining <= 0 {
                        state.pomodoroRemaining = state.pomodoroMinutes * 60
                    }
                    state.pomodoroRunning.toggle()
                } label: {
                    Text(state.pomodoroRunning ? "暂停" : "开始")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(state.pomodoroRunning
                                                   ? Color.white.opacity(0.7) : yellow))
                        .foregroundStyle(brown)
                }
                .buttonStyle(.plain)

                Button {
                    state.pomodoroRunning = false
                    state.pomodoroRemaining = state.pomodoroMinutes * 60
                } label: {
                    Text("重置")
                        .font(.system(size: 11, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.white.opacity(0.6)))
                        .foregroundStyle(brown.opacity(0.75))
                }
                .buttonStyle(.plain)
                .contentShape(Capsule())
            }
        }
        .onAppear {
            if state.pomodoroRemaining <= 0 {
                state.pomodoroRemaining = state.pomodoroMinutes * 60
            }
        }
    }

    // MARK: 手动
    private var manualTab: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                manualButton("在电脑前", active: state.mode == .working) { state.setWorking() }
                manualButton("去活动", active: state.mode == .away) { state.setAway() }
            }
            Toggle(isOn: $state.acceptReminderInManual) {
                Text("接受提醒")
                    .font(.system(size: 10)).foregroundStyle(brown)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
    }

    private func manualButton(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(Capsule().fill(active ? yellow : Color.white.opacity(0.5)))
                .foregroundStyle(brown.opacity(active ? 1 : 0.6))
        }
        .buttonStyle(.plain)
    }
}
