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
    @State private var confirmExit = false
    @State private var lastPoseAt = Date.distantPast
    @State private var showReward = false
    private let watchdog = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("RISE · 小猫陪你动一动").font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("完成一整组，收获 5 枚金币").font(.system(size: 13)).opacity(0.7)
                }
                Spacer()
                Label("\(state.coins)", systemImage: "circle.circle.fill")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .padding(12).background(Capsule().fill(MovementStyle.yellow))
                Button { requestExit() } label: { Image(systemName: "xmark").padding(12) }
                    .help("退出跟练")
            }
            ScrollView(.vertical) {
              HStack(alignment: .top, spacing: 20) {
                VStack(spacing: 12) {
                    cameraPanel
                    HStack {
                        Circle().fill(camera.running ? MovementStyle.sage : MovementStyle.brown.opacity(0.3))
                            .frame(width: 7, height: 7)
                        Text(camera.running ? "摄像头已开启 · 镜像画面" : "摄像头未开启")
                        Spacer()
                        if !camera.running && !workout.finished {
                            Button("开启摄像头") { camera.start() }
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
                Text("画面仅在本机识别，不录制、不上传。每次动作需抬起、保持、放下。").font(.system(size: 11)).opacity(0.65)
                Spacer()
                if workout.started && !workout.finished {
                    Button(workout.paused ? "继续跟练" : "暂停一下") { workout.togglePause() }
                        .disabled(!camera.running)
                }
                if workout.finished {
                    primary("带着金币回家") { state.movementOpen = false }
                } else if !workout.started {
                    primary("开始跟练 · 目标 \(workout.plannedSets * 5) 金币") {
                        state.acknowledgeReminder()
                        workout.start { state.coins += 5 }
                    }.disabled(workout.selected.isEmpty || !camera.running || !workout.visible)
                }
            }
        }
        .padding(24)
        .frame(width: 800, height: 730)
        .foregroundStyle(MovementStyle.brown)
        .background(MovementStyle.cream)
        .buttonStyle(.plain)
        .onAppear {
            camera.onPose = { pose, timestamp in
                lastPoseAt = Date()
                workout.receive(pose, at: timestamp)
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
        .confirmationDialog("结束本次跟练？", isPresented: $confirmExit) {
            Button("结束跟练") { state.movementOpen = false }
            Button("继续跟练", role: .cancel) { }
        } message: {
            Text("已完成的 \(workout.completedSets) 组、\(workout.earned) 枚金币会保留；未完成的一组不计奖励。")
        }
    }

    private var cameraPanel: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22).fill(MovementStyle.brown.opacity(0.09))
            if let image = camera.image {
                ZStack {
                    Image(decorative: image, scale: 1).resizable()
                    SkeletonView(pose: camera.pose)
                }
                .aspectRatio(CGFloat(image.width) / CGFloat(image.height), contentMode: .fit)
                .scaleEffect(x: -1, y: 1)
                .clipShape(RoundedRectangle(cornerRadius: 22))
            } else {
                VStack(spacing: 14) {
                    Image(systemName: workout.finished ? "checkmark.seal.fill" : "camera.fill")
                        .font(.system(size: 44)).foregroundStyle(MovementStyle.sage)
                    Text(workout.finished ? "跟练完成，辛苦啦！" : "给自己留一点活动空间")
                        .font(.system(size: 18, weight: .semibold))
                    Text("正对镜头，上半身、髋部和举起的双手都要入镜")
                        .font(.system(size: 12)).opacity(0.7)
                }
            }
        }.frame(width: 480, height: 360)
        .overlay(alignment: .topLeading) {
            Text(workout.finished ? "✓ 跟练完成" : (workout.visible ? "✓ 已找到你" : "等待完整姿势"))
                .font(.system(size: 12, weight: .semibold)).padding(10)
                .background(Capsule().fill(MovementStyle.cream.opacity(0.95))).padding(12)
        }
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("今天想怎么动？").font(.system(size: 16, weight: .bold))
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
            Text("每组依次完成所有已选动作，每个动作 3 次。可选 1–20 组。")
                .font(.system(size: 12)).opacity(0.7)
        }.padding(14).background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.65)))
    }

    private var liveProgress: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(workout.finished ? "全部完成" : "第 \(workout.completedSets + 1) / \(workout.targetSets) 组")
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
                Text(workout.paused ? "已暂停" : "姿势保持进度 · 放下双手后计为一次")
                    .font(.system(size: 11)).opacity(0.7)
            }
            if !workout.rewardMessage.isEmpty {
                Text(workout.rewardMessage).font(.system(size: 14, weight: .bold)).foregroundStyle(MovementStyle.sage)
            }
        }.padding(16).background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.65)))
    }

    private var guide: some View {
        VStack(spacing: 18) {
            Text("你的陪练小猫").font(.system(size: 14, weight: .semibold))
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
            Text(workout.current?.instruction ?? "跟着示意慢慢做，动作幅度以舒适为准。")
                .font(.system(size: 12)).lineSpacing(4).opacity(0.75)
        }.padding(16).background(RoundedRectangle(cornerRadius: 22).fill(MovementStyle.yellow.opacity(0.28)))
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
    private let edges: [(BodyJoint, BodyJoint)] = [
        (.leftWrist, .leftElbow), (.leftElbow, .leftShoulder),
        (.leftShoulder, .rightShoulder), (.rightShoulder, .rightElbow),
        (.rightElbow, .rightWrist), (.leftShoulder, .leftHip),
        (.rightShoulder, .rightHip), (.leftHip, .rightHip)
    ]
    var body: some View {
        Canvas { context, size in
            guard let pose else { return }
            func project(_ point: CGPoint) -> CGPoint {
                CGPoint(x: point.x * size.width, y: (1 - point.y) * size.height)
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
