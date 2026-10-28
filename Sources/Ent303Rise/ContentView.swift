import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var state: AppState

    /// 提醒间隔的分钟输入框内容
    @State private var minutesInput: String = "45"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            detectionArea
            timerBlock
            reminderArea
            settingsBlock
        }
        .padding(16)
        .frame(width: 320, height: 464, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
        )
        .onChange(of: state.intervalSeconds) { newValue in
            guard newValue >= 60 else {
                minutesInput = ""
                return
            }
            // 用户自己敲的就不用回写，避免打断输入
            if let typed = Int(minutesInput), typed * 60 == newValue { return }
            minutesInput = String(newValue / 60)
        }
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
            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary.opacity(0.75))
            }
            .buttonStyle(.plain)
            .help("退出 Ent303 Rise")
        }
    }

    // MARK: - 检测区

    @ViewBuilder
    private var detectionArea: some View {
        if state.detectionMode == .manual {
            manualButtons
        } else {
            autoStatusCard
        }
    }

    private var manualButtons: some View {
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

    private var autoStatusCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(state.mode == .working ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text("自动检测中")
                    .font(.system(size: 12, weight: .semibold))
                Text(state.autoStatusText)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }

    // MARK: - 计时

    private var timerBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("连续工作")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("目标 \(state.goalText)")
                    .font(.system(size: 10))
                    .foregroundStyle(state.isTestInterval ? .orange : .secondary)
            }
            Text(state.formattedDuration)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()
            ProgressView(value: state.progress)
                .progressViewStyle(.linear)
                .tint(state.progress >= 0.8 ? .orange : .accentColor)
        }
    }

    // MARK: - 提醒区

    @ViewBuilder
    private var reminderArea: some View {
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
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.orange.opacity(0.15))
            )
        } else {
            VStack(spacing: 8) {
                Image(systemName: "hourglass")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                Text("距下次提醒还有 \(state.remainingText)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Button("预览提醒") {
                    state.triggerReminder()
                }
                .font(.system(size: 10, weight: .semibold))
                .buttonStyle(.plain)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(0.16)))
            }
            .frame(maxWidth: .infinity, minHeight: 96)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
        }
    }

    // MARK: - 设置

    private var settingsBlock: some View {
        VStack(spacing: 10) {
            // 选项 1：提醒方式
            HStack(spacing: 8) {
                Text("提醒方式")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Picker("", selection: $state.detectionMode) {
                    ForEach(AppState.DetectionMode.allCases) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 148)
            }

            // 选项 2：提醒间隔（可自己输入，另有 10 秒测试项）
            HStack(spacing: 6) {
                Text("提醒间隔")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)

                if state.isTestInterval {
                    Text("测试：\(state.intervalSeconds) 秒")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.orange)
                    Button("退出测试") {
                        state.intervalSeconds = 45 * 60
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(0.14)))
                } else {
                    TextField("", text: $minutesInput)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.trailing)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .frame(width: 34)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.white.opacity(0.12))
                        )
                        .onChange(of: minutesInput) { v in
                            guard let n = Int(v), n >= 1, n <= 720 else { return }
                            state.intervalSeconds = n * 60
                        }
                    Text("分钟")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Button("10 秒测试") {
                        state.intervalSeconds = 10
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(0.14)))
                    .help("仅用于技术测试，不属于正式选项")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }
}
