import SwiftUI

/// 耳机按钮打开的 Focus 面板：三种提醒模式用 Tab 切换。
struct FocusPanel: View {
    @EnvironmentObject var state: AppState
    @Binding var tab: Int

    private let brown = Color(red: 0.36, green: 0.31, blue: 0.30)
    private let cream = Color(red: 1.0, green: 0.97, blue: 0.85)
    private let yellow = Color(red: 1.0, green: 0.81, blue: 0.39)

    private let tabs = ["自动检测", "番茄钟", "手动"]

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
                case 0: autoTab
                case 1: pomodoroTab
                default: manualTab
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(cream))
    }

    // MARK: 自动检测
    private var autoTab: some View {
        VStack(alignment: .leading, spacing: 6) {
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
            Toggle(isOn: $state.adaptive) {
                Text("自适应")
                    .font(.system(size: 10)).foregroundStyle(brown)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            Text("开启后初期提醒间隔更长，逐步逼近推荐值")
                .font(.system(size: 9)).foregroundStyle(brown.opacity(0.5))
        }
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
            Button {
                state.pomodoroRunning.toggle()
            } label: {
                Text(state.pomodoroRunning ? "停止" : "开始")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(brown)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(state.pomodoroRunning ? Color.white.opacity(0.7) : yellow))
            }
            .buttonStyle(.plain)
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
