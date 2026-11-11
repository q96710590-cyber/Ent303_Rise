import Foundation
import Combine

final class MovementSession: ObservableObject {
    @Published var selected: Set<Movement> = Set(Movement.allCases)
    @Published var plannedSets = 3
    @Published private(set) var started = false
    @Published private(set) var paused = false
    @Published private(set) var completedSets = 0
    @Published private(set) var actionIndex = 0
    @Published private(set) var repetitions = 0
    @Published private(set) var engine = MovementEngine()
    @Published private(set) var visible = false
    @Published private(set) var rewardMessage = ""
    private(set) var routine: [Movement] = []
    private(set) var targetSets = 0
    private var credit: (() -> Void)?
    let repsPerAction = 3

    var finished: Bool { started && completedSets == targetSets }
    var current: Movement? { routine.indices.contains(actionIndex) ? routine[actionIndex] : nil }
    var earned: Int { completedSets * 5 }
    var progress: Double {
        guard targetSets > 0, !routine.isEmpty else { return 0 }
        return Double(completedSets * routine.count * repsPerAction + actionIndex * repsPerAction + repetitions)
            / Double(targetSets * routine.count * repsPerAction)
    }
    var cue: String {
        if finished { return "喵！目标完成，\(earned) 枚金币已经进入钱包啦。" }
        if paused { return "休息一下吧，准备好再继续。" }
        if !started { return "选好动作和组数，我们一起动一动！" }
        if !visible { return "请正对镜头，退后一点，让肩、肘、双手和髋部都入镜。画面中只留一人哦。" }
        switch engine.phase {
        case .ready: return "先把双手自然放下，让我看看准备姿势。"
        case .target: return (current?.instruction ?? "") + " 稳稳保持 0.8 秒哦！"
        case .lower: return "很好！双手自然放下，完成这一次。"
        }
    }

    func start(credit: @escaping () -> Void) {
        guard !started, !selected.isEmpty else { return }
        routine = Movement.allCases.filter { selected.contains($0) }
        targetSets = min(20, max(1, plannedSets))
        self.credit = credit
        engine.reset()
        started = true
    }

    func togglePause() {
        guard started, !finished else { return }
        paused.toggle()
        engine.reset()
    }

    func invalidateTracking() { visible = false; engine.reset() }

    func receive(_ pose: BodyPose?, at time: TimeInterval) {
        visible = pose?.isVisible == true
        guard started, !paused, !finished, let current else { return }
        guard engine.consume(pose, movement: current, at: time) else { return }
        rewardMessage = ""
        repetitions += 1
        if repetitions == repsPerAction {
            repetitions = 0
            actionIndex += 1
            engine.reset()
            if actionIndex == routine.count {
                actionIndex = 0
                completedSets += 1
                // Only this transition credits a set. Pausing, closing and view redraws cannot credit it again.
                credit?()
                rewardMessage = "第 \(completedSets) 组完成！+5 金币"
            }
        }
    }
}
