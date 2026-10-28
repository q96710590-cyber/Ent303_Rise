import SwiftUI

struct ContentView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            modeRow
            timerBlock
            reminderArea
            settingsRow
        }
        .padding(16)
        .frame(width: 320, height: 380, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - 顶部

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "pawprint.fill")
                .font(.system(size: 14, weight: .semibold))
            Text("Ent303 Rise")
                .font(.system(size: 14, weight: .bold))
            Spacer()
            Circle()
                .fill(state.mode == .working ? Color.green : Color.gray.opacity(0.5))
                .frame(width: 8, height: 8)
            Text(state.mode == .working ? "计时中" : "已暂停")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 两个手动确认图标

    private var modeRow: some View {
        HStack(spacing: 10) {
            modeButton(icon: "desktopcomputer",
                       label: "在电脑前",
                       active: state.mode == .working) {
                state.setWorking()
            }
            modeButton(icon: "figure.walk",
                       label: "去活动",
                       active: state.mode == .away) {
                state.setAway()
            }
        }
    }

    private func modeButton(icon: String,
                            label: String,
                            active: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .medium))
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(active ? Color.accentColor.opacity(0.9)
                                 : Color.white.opacity(0.08))
            )
            .foregroundStyle(active ? Color.white : Color.primary)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(active ? Color.clear
                                         : Color.white.opacity(0.10),
                                  lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 计时

    private var timerBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("连续工作")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("目标 \(state.intervalMinutes) 分钟")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Text(state.formattedDuration)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()
            ProgressView(value: state.progress)
                .progressViewStyle(.linear)
                .tint(state.progress >= 0.8 ? .orange : .accentColor)
        }
    }

    // MARK: - 提醒区（固定高度，避免窗口跳动）

    private var reminderArea: some View {
        Group {
            if let r = state.reminder {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: r.icon)
                            .font(.system(size: 15, weight: .semibold))
                        Text(r.title)
                            .font(.system(size: 13, weight: .bold))
                    }
                    Text(r.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        state.acknowledgeReminder()
                    } label: {
                        Text("我起来了")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(Color.orange.opacity(0.85))
                            )
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.orange.opacity(0.15))
                )
            } else {
                Color.clear.frame(height: 96)
            }
        }
    }

    // MARK: - 设置

    private var settingsRow: some View {
        HStack(spacing: 10) {
            Text("提醒间隔")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Stepper(value: $state.intervalMinutes, in: 1...120, step: 1) {
                Text("\(state.intervalMinutes) 分钟")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
            }
            .labelsHidden()
            Text("\(state.intervalMinutes) 分钟")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
            Spacer()
            Button("测试提醒") {
                state.triggerReminder()
            }
            .font(.system(size: 11, weight: .semibold))
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.10))
            )
        }
    }
}
