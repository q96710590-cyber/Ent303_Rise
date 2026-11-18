import Foundation

enum Movement: String, CaseIterable, Identifiable {
    case reach, wings, curl
    var id: String { rawValue }
    var title: String {
        switch self {
        case .reach: return "向上伸展"
        case .wings: return "双臂侧平举"
        case .curl: return "双臂弯举"
        }
    }
    var instruction: String {
        switch self {
        case .reach: return "双手举过头顶，保持片刻，再自然放下。"
        case .wings: return "双臂向两侧展开至肩高，保持片刻，再放下。"
        case .curl: return "上臂靠近身体，双手抬向肩膀，再伸直放下。"
        }
    }
    var symbol: String {
        switch self {
        case .reach: return "figure.arms.open"
        case .wings: return "figure.stand"
        case .curl: return "figure.strengthtraining.functional"
        }
    }
}

enum BodyJoint: CaseIterable {
    case leftShoulder, rightShoulder, leftElbow, rightElbow
    case leftWrist, rightWrist, leftHip, rightHip
}

struct BodyPose {
    /// Vision normalized coordinates, origin at bottom left, unmirrored.
    let points: [BodyJoint: CGPoint]

    var isVisible: Bool { BodyJoint.allCases.allSatisfy { points[$0] != nil } }

    func matches(_ movement: Movement) -> Bool {
        guard isVisible,
              let ls = points[.leftShoulder], let rs = points[.rightShoulder],
              let le = points[.leftElbow], let re = points[.rightElbow],
              let lw = points[.leftWrist], let rw = points[.rightWrist],
              let lh = points[.leftHip], let rh = points[.rightHip] else { return false }
        let torso = (ls.y + rs.y - lh.y - rh.y) / 2
        guard torso > 0.10, abs(ls.y - rs.y) < torso * 0.35 else { return false }
        switch movement {
        case .reach:
            return lw.y > ls.y + torso * 0.65 && rw.y > rs.y + torso * 0.65
                && le.y > ls.y && re.y > rs.y
        case .wings:
            return abs(lw.y - ls.y) < torso * 0.23 && abs(rw.y - rs.y) < torso * 0.23
                && abs(le.y - ls.y) < torso * 0.23 && abs(re.y - rs.y) < torso * 0.23
                && abs(lw.x - ls.x) > torso * 0.65 && abs(rw.x - rs.x) > torso * 0.65
                && (lw.x - ls.x) * (rw.x - rs.x) < 0
        case .curl:
            return distance(lw, ls) < torso * 0.45 && distance(rw, rs) < torso * 0.45
                && le.y < ls.y - torso * 0.28 && re.y < rs.y - torso * 0.28
        }
    }

    var isNeutral: Bool {
        guard isVisible, let ls = points[.leftShoulder], let rs = points[.rightShoulder],
              let lw = points[.leftWrist], let rw = points[.rightWrist],
              let lh = points[.leftHip], let rh = points[.rightHip] else { return false }
        let torso = (ls.y + rs.y - lh.y - rh.y) / 2
        return torso > 0.10 && lw.y < ls.y - torso * 0.65 && rw.y < rs.y - torso * 0.65
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}

/// Real elapsed time, stable holds and a complete down/up/down cycle prevent frame-count rewards.
struct MovementEngine {
    enum Phase: Equatable { case ready, target, lower }
    private(set) var phase: Phase = .ready
    private var stableSince: TimeInterval?
    private var lastTimestamp: TimeInterval?
    private(set) var holdProgress: Double = 0

    mutating func reset() {
        phase = .ready
        stableSince = nil
        lastTimestamp = nil
        holdProgress = 0
    }

    mutating func consume(_ pose: BodyPose?, movement: Movement, at time: TimeInterval) -> Bool {
        if let lastTimestamp, time - lastTimestamp > 0.5 || time <= lastTimestamp { reset() }
        lastTimestamp = time
        guard let pose, pose.isVisible else { reset(); return false }
        let matches = phase == .target ? pose.matches(movement) : pose.isNeutral
        guard matches else { stableSince = nil; holdProgress = 0; return false }
        if stableSince == nil { stableSince = time }
        let duration = phase == .target ? 0.8 : 0.35
        holdProgress = min(1, (time - (stableSince ?? time)) / duration)
        guard holdProgress >= 1 else { return false }
        stableSince = nil
        holdProgress = 0
        switch phase {
        case .ready: phase = .target
        case .target: phase = .lower
        case .lower: phase = .target; return true
        }
        return false
    }
}
