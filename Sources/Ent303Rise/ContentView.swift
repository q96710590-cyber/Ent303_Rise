import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var state: AppState

    // 提醒间隔的三段输入：时 / 分 / 秒
    @State private var hoursInput: String = "0"
    @State private var minutesInput: String = "45"
    @State private var secondsInput: String = "0"

    enum DurationFocus: Hashable { case hours, minutes, seconds }
    @FocusState private var focus: DurationFocus?

    // 缩略图标由 AppKit 的 IconView 负责（见 main.swift），
    // 这里只渲染详情界面，缩略时整个 hosting view 会被隐藏。
    var body: some View {
        expandedContent
    }

    // MARK: - 详情界面

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            detectionArea
            timerBlock
            reminderArea
            settingsBlock
        }
        .padding(16)
        .frame(width: 320, height: 504, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                // 点卡片空白处 = 失焦保存
                .onTapGesture { dismissFocus() }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
        )
        // 外部改动（测试按钮 / 箭头）→ 回写输入框；正在编辑时不打扰
        .onChange(of: state.intervalSeconds) { newValue in
            guard focus == nil else { return }
            applyToInputs(newValue)
        }
        // 聚焦变化：记录编辑态；失焦即提交
        .onChange(of: focus) { newValue in
            state.setEditing(newValue != nil)
            if newValue == nil { commit() }
        }
    }

    /// 回车 / 失去焦点时提交：解析三段输入，规范化后写回状态
    private func commit() {
        let rawH = max(0, Int(hoursInput) ?? 0)
        let rawM = max(0, Int(minutesInput) ?? 0)
        let rawS = max(0, Int(secondsInput) ?? 0)
        // 不逐段截断，允许 90 分这种写法，交给归一化处理
        let total = min(rawH * 3600 + rawM * 60 + rawS, 99 * 3600)

        guard total >= 1 else {
            applyToInputs(state.intervalSeconds)
            return
        }

        state.intervalSeconds = total

        let normH = total / 3600
        let normM = (total % 3600) / 60
        let normS = total % 60
        if normH != rawH || normM != rawM || normS != rawS {
            applyToInputs(total)   // 例如 90 分 → 1 时 30 分
        }
    }

    private func applyToInputs(_ seconds: Int) {
        hoursInput = String(seconds / 3600)
        minutesInput = String((seconds % 3600) / 60)
        secondsInput = String(seconds % 60)
    }

    private func dismissFocus() {
        focus = nil
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    /// 上下箭头：按分钟增减，保留秒数
    private var minutesStepperBinding: Binding<Int> {
        Binding(
            get: { state.intervalSeconds / 60 },
            set: { newMinutes in
                let remainder = state.intervalSeconds % 60
                state.intervalSeconds = max(60, newMinutes * 60 + remainder)
            }
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
            Button {
                state.collapseToIcon()
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary.opacity(0.75))
            }
            .buttonStyle(.plain)
            .help("缩略为图标")
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

            Divider().opacity(0.25)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
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

                if state.isTestInterval {
                    Text("当前为测试间隔，点「退出测试」恢复 45 分钟")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange.opacity(0.9))
                } else {
                    HStack(spacing: 6) {
                        durationField($hoursInput, unit: "时", field: .hours)
                        durationField($minutesInput, unit: "分", field: .minutes)
                        durationField($secondsInput, unit: "秒", field: .seconds)
                        Spacer(minLength: 4)
                        Stepper("", value: minutesStepperBinding, in: 1...720, step: 1)
                            .labelsHidden()
                            .help("上下箭头按分钟调整")
                    }
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

    private func durationField(_ text: Binding<String>,
                               unit: String,
                               field: DurationFocus) -> some View {
        HStack(spacing: 3) {
            TextField("", text: text)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .frame(width: 22)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(focus == field ? 0.20 : 0.12))
                )
                .focused($focus, equals: field)
                // 回车只负责结束编辑，提交交给 focus 变化
                .onSubmit { dismissFocus() }
            Text(unit)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }
}
