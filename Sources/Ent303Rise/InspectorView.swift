import SwiftUI
import AppKit

/// 检查台：与主面板共用同一个 AppState，
/// 用于查看实时状态、触发各种状态、逐帧检查视觉素材。
struct InspectorView: View {
    @EnvironmentObject var state: AppState

    @State private var frameIndex = 0
    @State private var playing = true

    private let frameCount = 8
    private let player = Timer.publish(every: 0.45, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                titleBar
                statusSection
                controlSection
                assetSection
            }
            .padding(18)
        }
        .frame(width: 480, height: 760)
        .background(.regularMaterial)
        .onReceive(player) { _ in
            guard playing else { return }
            frameIndex = (frameIndex + 1) % frameCount
        }
    }

    // MARK: - 标题

    private var titleBar: some View {
        HStack(spacing: 8) {
            // 窗口标题栏已有标题，这里只放标记与提示，避免重复
            Text("技术测试台")
                .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.orange.opacity(0.22)))
                .foregroundStyle(.orange)
            Spacer()
            Text("与主面板共用同一状态")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 状态

    private var statusSection: some View {
        section("运行状态") {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 20),
                    GridItem(.flexible(), spacing: 20)
                ],
                spacing: 6
            ) {
                row("检测方式", state.detectionMode.rawValue)
                row("计时状态", state.mode == .working ? "计时中" : "已暂停")
                row("连续工作", state.formattedDuration)
                row("目标间隔", state.goalText)
                row("进度", String(format: "%.1f%%", state.progress * 100))
                row("系统空闲", String(format: "%.1f 秒", state.systemIdleSeconds))
                row("鼠标在窗口内", state.isHovering ? "是" : "否")
                row("正在编辑输入", state.isEditing ? "是" : "否")
                row("有未处理提醒", state.reminder != nil ? "是" : "否")
                row("已缩略为图标", state.collapsed ? "是" : "否")
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
        }
    }

    // MARK: - 操作

    private var controlSection: some View {
        section("操作") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    actionButton("立即提醒", tint: .orange) { state.triggerReminder() }
                    actionButton("我起来了", tint: .green) { state.acknowledgeReminder() }
                }
                HStack(spacing: 8) {
                    actionButton("10 秒测试", tint: .orange) { state.intervalSeconds = 10 }
                    actionButton("退出测试", tint: .secondary) { state.intervalSeconds = 45 * 60 }
                }
                HStack(spacing: 8) {
                    actionButton("缩略为图标", tint: .accentColor) { state.collapseToIcon() }
                    actionButton("展开详情", tint: .accentColor) { state.expand() }
                }
            }
        }
    }

    private func actionButton(_ title: String,
                              tint: Color,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(tint.opacity(0.16))
                )
                .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 素材

    private var assetSection: some View {
        section("视觉素材") {
            VStack(spacing: 10) {
                // 逐帧播放
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.black.opacity(0.06))
                    if let img = catImage(frameIndex) {
                        Image(nsImage: img)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(maxWidth: 420, maxHeight: 180)
                            .padding(10)
                    } else {
                        Text("找不到素材")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 200)
                .clipped()

                HStack(spacing: 10) {
                    Button { frameIndex = (frameIndex + frameCount - 1) % frameCount } label: {
                        Image(systemName: "backward.frame.fill")
                    }
                    .buttonStyle(.plain)

                    Button { playing.toggle() } label: {
                        Image(systemName: playing ? "pause.fill" : "play.fill")
                    }
                    .buttonStyle(.plain)

                    Button { frameIndex = (frameIndex + 1) % frameCount } label: {
                        Image(systemName: "forward.frame.fill")
                    }
                    .buttonStyle(.plain)

                    Text("第 \(frameIndex + 1) / \(frameCount) 帧")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("猫形 S 融化动画")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                // 一行缩略图
                HStack(spacing: 4) {
                    ForEach(0..<frameCount, id: \.self) { i in
                        Button { frameIndex = i; playing = false } label: {
                            Group {
                                if let img = catImage(i) {
                                    Image(nsImage: img)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                } else {
                                    Color.gray.opacity(0.2)
                                }
                            }
                            .frame(width: 48, height: 34)
                            .padding(2)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(i == frameIndex ? Color.accentColor.opacity(0.25)
                                                          : Color.black.opacity(0.05))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Divider().opacity(0.4)

                // 图标素材
                HStack(spacing: 12) {
                    if let logo = logoImage {
                        Image(nsImage: logo)
                            .resizable()
                            .frame(width: 48, height: 48)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("缩略图标 logo.png")
                            .font(.system(size: 11, weight: .medium))
                        Text("512×512，用于缩略态的圆形图标")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        }
    }

    private func catImage(_ index: Int) -> NSImage? {
        guard let url = Bundle.main.url(forResource: "cat_\(index)",
                                        withExtension: "png",
                                        subdirectory: "cat") else { return nil }
        return NSImage(contentsOf: url)
    }

    private var logoImage: NSImage? {
        guard let url = Bundle.main.url(forResource: "logo", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }

    // MARK: - 分区容器

    @ViewBuilder
    private func section<Content: View>(_ title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }
}
