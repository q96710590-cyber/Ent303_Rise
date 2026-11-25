import SwiftUI
import AppKit

private enum MovementStyle {
    static let brown = Color(red: 0.36, green: 0.31, blue: 0.30)
    static let cream = Color(red: 1, green: 0.98, blue: 0.88)
    static let yellow = Color(red: 1, green: 0.81, blue: 0.39)
    static let sage = Color(red: 0.39, green: 0.53, blue: 0.43)
}

struct MovementView: View {
    @EnvironmentObject var state: AppState
    @StateObject private var camera = MovementCamera()
    @StateObject private var workout = MovementSession()
    /// 完成一次动作后的小结报告
    @State private var report: MovementReport?
    @State private var confirmExit = false
    @State private var lastPoseAt = Date.distantPast
    @State private var showReward = false
    private let watchdog = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Lang.t("RISE · 小猫陪你动一动", "RISE · Move with your cat")).font(.system(size: 24, weight: .bold, design: .rounded))
                    Text(Lang.t("完成一整组，收获 5 枚金币", "Finish a set, earn 5 coins")).font(.system(size: 13)).opacity(0.7)
                }
                Spacer()
                Label("\(state.coins)", systemImage: "circle.circle.fill")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .padding(12).background(Capsule().fill(MovementStyle.yellow))
                Button { requestExit() } label: { Image(systemName: "xmark").padding(12) }
                    .help(Lang.t("退出跟练", "Quit workout"))
            }
            ScrollView(.vertical) {
              HStack(alignment: .top, spacing: 20) {
                VStack(spacing: 12) {
                    cameraPanel
                    HStack {
                        Circle().fill(camera.running ? MovementStyle.sage : MovementStyle.brown.opacity(0.3))
                            .frame(width: 7, height: 7)
                        Text(camera.running ? Lang.t("摄像头已开启 · 镜像画面", "Camera on · mirrored") : Lang.t("摄像头未开启", "Camera off"))
                        Spacer()
                        if !camera.running && !workout.finished {
                            Button(Lang.t("开启摄像头", "Enable camera")) { camera.start() }
                        } else if camera.running && !workout.started && !workout.finished {
                            Button(Lang.t("开始识别", "Start detecting")) { maybeAutoStart(force: true) }
                        }
                    }.font(.system(size: 12))
                    Text(camera.message).font(.system(size: 12)).opacity(0.75)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if workout.started { liveProgress } else { setup }
                }.frame(width: 480)
                guide.frame(width: 230)
              }
            }
            HStack {
                Text(Lang.t("画面仅在本机识别，不录制、不上传。每次动作需抬起、保持、放下。", "Processed on-device. No recording, no upload. Raise, hold, lower.")).font(.system(size: 11)).opacity(0.65)
                Spacer()
                if workout.started && !workout.finished {
                    Button(workout.paused ? Lang.t("继续跟练", "Resume") : Lang.t("暂停一下", "Pause")) { workout.togglePause() }
                        .disabled(!camera.running)
                }
                // 右下角唯一的动作：结束并回家
                primary(state.t(Lang.t("我回来了，结束", "I'm back · Finish"), "I'm back · Finish")) {
                    state.movementOpen = false
                }
            }
        }
        .padding(24)
        .frame(width: 800, height: 730)
        .foregroundStyle(MovementStyle.brown)
        .background(MovementStyle.cream)
        .buttonStyle(.plain)
        .overlay {
            if let report {
                reportCard(report)
                    .transition(.scale(scale: 0.86).combined(with: .opacity))
            }
        }
        .onAppear {
            camera.onPose = { pose, timestamp in
                lastPoseAt = Date()
                workout.receive(pose, at: timestamp)
            }
            // 打开即自动开启摄像头，用户无需手动点（demo 截图模式除外）
            if !CommandLine.arguments.contains("--demo-report") { camera.start() }
            if CommandLine.arguments.contains("--demo-report") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    let rep = state.recordMovement(action: Lang.t("向上伸展", "Reach up"))
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { report = rep }
                }
            }
        }
        .onDisappear { camera.stop(); camera.onPose = nil }
        .onChange(of: workout.finished) { done in if done { camera.stop() } }
        .task(id: workout.completedSets) {
            guard workout.completedSets > 0 else { return }
            showReward = true
            do { try await Task.sleep(nanoseconds: 2_400_000_000) }
            catch { return }
            showReward = false
        }
        .onReceive(watchdog) { now in
            if now.timeIntervalSince(lastPoseAt) > 0.7 { workout.invalidateTracking() }
        }
        .onChange(of: camera.running) { _ in maybeAutoStart() }
        .onChange(of: workout.visible) { _ in maybeAutoStart() }
        .confirmationDialog(Lang.t("结束本次跟练？", "End this workout?"), isPresented: $confirmExit) {
            Button(Lang.t("结束跟练", "End workout")) { state.movementOpen = false }
            Button(Lang.t("继续跟练", "Resume"), role: .cancel) { }
        } message: {
            Text("已完成的 \(workout.completedSets) 组、\(workout.earned) 枚金币会保留；未完成的一组不计奖励。")
        }
    }

    /// 完成一次后的简短报告，居中显示，几秒后自动消失
    private func reportCard(_ r: MovementReport) -> some View {
        VStack(spacing: 10) {
            Text(Lang.t("完成一次「\(r.action)」", "Done · \(r.action)"))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(MovementStyle.brown)
            Text(Lang.t("+ \(r.gained) 金币", "+\(r.gained) coins"))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(MovementStyle.yellow)

            HStack(spacing: 18) {
                reportStat(Lang.t("坚持", "Days"), Lang.t("\(r.dayCount) 天", "\(r.dayCount)d"))
                reportStat(Lang.t("累计", "Total"), Lang.t("\(r.totalReps) 次", "\(r.totalReps)x"))
                reportStat(Lang.t("少坐", "Less sitting"), r.avoidedText)
            }
            .padding(.top, 2)

            if r.isNewDay {
                Text(Lang.t("新的一天，继续保持", "New day, keep it up"))
                    .font(.system(size: 11))
                    .foregroundStyle(MovementStyle.sage)
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(MovementStyle.cream)
                .shadow(color: MovementStyle.brown.opacity(0.18), radius: 18, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(MovementStyle.yellow.opacity(0.6), lineWidth: 1.5)
        )
        .allowsHitTesting(false)
    }

    private func reportStat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(MovementStyle.brown)
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(MovementStyle.brown.opacity(0.55))
        }
    }

    private var cameraPanel: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22).fill(MovementStyle.brown.opacity(0.09))
            if let image = camera.image {
                ZStack {
                    Image(decorative: image, scale: 1).resizable().scaledToFill()
                    SkeletonView(pose: camera.pose,
                                 imageSize: CGSize(width: image.width, height: image.height))
                }
                .clipped()
                .scaleEffect(x: -1, y: 1)
                .clipShape(RoundedRectangle(cornerRadius: 22))
            } else {
                VStack(spacing: 14) {
                    Image(systemName: workout.finished ? "checkmark.seal.fill" : "camera.fill")
                        .font(.system(size: 44)).foregroundStyle(MovementStyle.sage)
                    Text(workout.finished ? Lang.t("跟练完成，辛苦啦！", "Workout complete. Nice work!") : Lang.t("给自己留一点活动空间", "Give yourself some room"))
                        .font(.system(size: 18, weight: .semibold))
                    Text(Lang.t("正对镜头，让肩、肘和双手都入镜即可", "Face the camera — shoulders, elbows and hands in frame"))
                        .font(.system(size: 12)).opacity(0.7)
                }
            }
        }
        .frame(width: 340, height: 470)
        .clipped()
        .overlay(alignment: .topLeading) {
            Text(workout.finished ? Lang.t("✓ 跟练完成", "✓ Workout done") : (workout.visible ? Lang.t("✓ 已找到你", "✓ Got you") : Lang.t("等待完整姿势", "Waiting for full pose")))
                .font(.system(size: 12, weight: .semibold)).padding(10)
                .background(Capsule().fill(MovementStyle.cream.opacity(0.95))).padding(12)
        }
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Lang.t("今天想怎么动？", "How do you want to move?")).font(.system(size: 16, weight: .bold))
            HStack(spacing: 8) {
                ForEach(Movement.allCases) { movement in
                    Button {
                        if workout.selected.contains(movement) { workout.selected.remove(movement) }
                        else { workout.selected.insert(movement) }
                    } label: {
                        Label(movement.title, systemImage: workout.selected.contains(movement) ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 12, weight: .semibold)).padding(10)
                            .background(RoundedRectangle(cornerRadius: 12).fill(workout.selected.contains(movement) ? MovementStyle.yellow : .white))
                    }
                }
            }
            Stepper(value: $workout.plannedSets, in: 1...20) {
                Text("\(workout.plannedSets) 组  ·  预计收获 \(workout.plannedSets * 5) 金币")
                    .font(.system(size: 14, weight: .semibold))
            }
            Text(Lang.t("每组依次完成所有已选动作，每个动作 3 次。可选 1–20 组。", "Complete the selected moves in order. 1–20 sets."))
                .font(.system(size: 12)).opacity(0.7)
        }.padding(14).background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.65)))
    }

    private var liveProgress: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(workout.finished ? Lang.t("全部完成", "All done") : "第 \(workout.completedSets + 1) / \(workout.targetSets) 组")
                    .font(.system(size: 17, weight: .bold))
                Spacer()
                Text("已入账 +\(workout.earned) 金币").font(.system(size: 13, weight: .semibold))
            }
            ProgressView(value: workout.progress).tint(MovementStyle.sage)
            if !workout.finished, let current = workout.current {
                HStack {
                    Text("\(workout.actionIndex + 1). \(current.title)")
                    Spacer()
                    Text("\(workout.repetitions) / \(workout.repsPerAction) 次")
                }.font(.system(size: 15, weight: .semibold))
                ProgressView(value: workout.engine.holdProgress).tint(MovementStyle.yellow)
                Text(workout.paused ? Lang.t("已暂停", "Paused") : Lang.t("姿势保持进度 · 放下双手后计为一次", "Hold progress · lower your arms to count one"))
                    .font(.system(size: 11)).opacity(0.7)
            }
            if !workout.rewardMessage.isEmpty {
                Text(workout.rewardMessage).font(.system(size: 14, weight: .bold)).foregroundStyle(MovementStyle.sage)
            }
        }.padding(16).background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.65)))
    }

    private var guide: some View {
        VStack(spacing: 18) {
            Text(Lang.t("你的陪练小猫", "Your coach cat")).font(.system(size: 14, weight: .semibold))
            ZStack {
                MovementAssetView(name: "RISE_cat_tail_only_cropped", playing: !workout.paused)
                    .frame(width: 150, height: 145)
                if showReward {
                    MovementAssetView(name: "RISE_gold_coin_rise_fade_transparent", playing: true)
                        .frame(width: 160, height: 160).offset(x: 30, y: -20)
                        .id(workout.completedSets)
                }
            }.frame(height: 145)
            Text(workout.cue).font(.system(size: 15, weight: .medium)).lineSpacing(5)
                .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
                .padding(16).background(RoundedRectangle(cornerRadius: 18).fill(.white))
            MovementDemo(movement: workout.started ? (workout.current ?? .reach) : .reach)
                .frame(height: 125)
            Text(workout.current?.instruction ?? Lang.t("跟着示意慢慢做，动作幅度以舒适为准。", "Follow the demo — keep it comfortable."))
                .font(.system(size: 12)).lineSpacing(4).opacity(0.75)
        }.padding(16).background(RoundedRectangle(cornerRadius: 22).fill(MovementStyle.yellow.opacity(0.28)))
    }

    /// 相机就绪且识别到完整姿势时自动开始，不需要用户点确认
    private func maybeAutoStart(force: Bool = false) {
        guard camera.running, (force || workout.visible),
              !workout.started, !workout.finished,
              !workout.selected.isEmpty else { return }
        state.acknowledgeReminder()
        workout.start {
            state.coins += 5                       // 立即入账
            let action = workout.routine.first?.title ?? Lang.t("动作", "Move")
            let rep = state.recordMovement(action: action)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { report = rep }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.6) {
                withAnimation(.easeOut(duration: 0.25)) { report = nil }
            }
        }
    }

    private func primary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 14, weight: .bold)).padding(.horizontal, 18).padding(.vertical, 12)
                .background(Capsule().fill(MovementStyle.yellow))
        }.buttonStyle(.plain)
    }

    private func requestExit() {
        if workout.started && !workout.finished { confirmExit = true }
        else { state.movementOpen = false }
    }
}

private struct SkeletonView: View {
    let pose: BodyPose?
    var imageSize: CGSize? = nil
    private let edges: [(BodyJoint, BodyJoint)] = [
        (.leftWrist, .leftElbow), (.leftElbow, .leftShoulder),
        (.leftShoulder, .rightShoulder), (.rightShoulder, .rightElbow),
        (.rightElbow, .rightWrist), (.leftShoulder, .leftHip),
        (.rightShoulder, .rightHip), (.leftHip, .rightHip)
    ]
    var body: some View {
        Canvas { context, size in
            guard let pose else { return }
            // 竖版面板是 center-crop 显示，骨架必须按同一变换换算，否则会错位
            var box = size
            var offset = CGPoint.zero
            if let img = imageSize, img.width > 0, img.height > 0 {
                let scale = max(size.width / img.width, size.height / img.height)
                box = CGSize(width: img.width * scale, height: img.height * scale)
                offset = CGPoint(x: (size.width - box.width) / 2,
                                 y: (size.height - box.height) / 2)
            }
            func project(_ point: CGPoint) -> CGPoint {
                CGPoint(x: offset.x + point.x * box.width,
                        y: offset.y + (1 - point.y) * box.height)
            }
            for (a, b) in edges {
                guard let p = pose.points[a], let q = pose.points[b] else { continue }
                var path = Path(); path.move(to: project(p)); path.addLine(to: project(q))
                context.stroke(path, with: .color(MovementStyle.yellow), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            }
            for p in pose.points.values {
                let point = project(p)
                context.fill(Path(ellipseIn: CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)), with: .color(.white))
            }
        }
    }
}

/// A looping down/target guide accompanies the original cat artwork.
private struct MovementDemo: View {
    let movement: Movement
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.05)) { timeline in
            let raised = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 4) > 2
            Canvas { context, size in
                let cx = size.width / 2
                let shoulderY = 40.0
                let leftHand: CGPoint
                let rightHand: CGPoint
                if raised {
                    switch movement {
                    case .reach:
                        leftHand = CGPoint(x: cx - 26, y: 4); rightHand = CGPoint(x: cx + 26, y: 4)
                    case .wings:
                        leftHand = CGPoint(x: cx - 66, y: 40); rightHand = CGPoint(x: cx + 66, y: 40)
                    case .curl:
                        leftHand = CGPoint(x: cx - 22, y: 40); rightHand = CGPoint(x: cx + 22, y: 40)
                    }
                } else {
                    leftHand = CGPoint(x: cx - 26, y: 91); rightHand = CGPoint(x: cx + 26, y: 91)
                }
                var path = Path()
                path.move(to: CGPoint(x: cx, y: 34)); path.addLine(to: CGPoint(x: cx, y: 82))
                for side in [-1.0, 1.0] {
                    let shoulder = CGPoint(x: cx + side * 16, y: shoulderY)
                    path.move(to: CGPoint(x: cx, y: shoulderY)); path.addLine(to: shoulder)
                    if raised && movement == .curl { path.addLine(to: CGPoint(x: cx + side * 24, y: 68)) }
                    path.addLine(to: side < 0 ? leftHand : rightHand)
                    path.move(to: CGPoint(x: cx, y: 82)); path.addLine(to: CGPoint(x: cx + side * 23, y: 118))
                }
                context.stroke(path, with: .color(MovementStyle.sage), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                context.stroke(Path(ellipseIn: CGRect(x: cx - 11, y: 7, width: 22, height: 22)), with: .color(MovementStyle.sage), lineWidth: 5)
            }
        }
    }
}
