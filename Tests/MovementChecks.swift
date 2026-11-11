import Foundation

@main
struct MovementChecks {
    static func pose(_ movement: Movement? = nil) -> BodyPose {
        var points: [BodyJoint: CGPoint] = [
            .leftShoulder: CGPoint(x: 0.4, y: 0.65), .rightShoulder: CGPoint(x: 0.6, y: 0.65),
            .leftHip: CGPoint(x: 0.42, y: 0.35), .rightHip: CGPoint(x: 0.58, y: 0.35),
            .leftElbow: CGPoint(x: 0.38, y: 0.48), .rightElbow: CGPoint(x: 0.62, y: 0.48),
            .leftWrist: CGPoint(x: 0.38, y: 0.35), .rightWrist: CGPoint(x: 0.62, y: 0.35)
        ]
        switch movement {
        case .reach:
            points[.leftElbow] = CGPoint(x: 0.36, y: 0.78)
            points[.rightElbow] = CGPoint(x: 0.64, y: 0.78)
            points[.leftWrist] = CGPoint(x: 0.37, y: 0.94)
            points[.rightWrist] = CGPoint(x: 0.63, y: 0.94)
        case .wings:
            points[.leftElbow] = CGPoint(x: 0.28, y: 0.65)
            points[.rightElbow] = CGPoint(x: 0.72, y: 0.65)
            points[.leftWrist] = CGPoint(x: 0.12, y: 0.65)
            points[.rightWrist] = CGPoint(x: 0.88, y: 0.65)
        case .curl:
            points[.leftWrist] = CGPoint(x: 0.39, y: 0.64)
            points[.rightWrist] = CGPoint(x: 0.61, y: 0.64)
        case nil: break
        }
        return BodyPose(points: points)
    }

    static func main() {
        for action in Movement.allCases {
            precondition(pose(action).matches(action), "Target geometry: \(action)")
            precondition(!pose().matches(action), "Neutral cannot be a target")
            var engine = MovementEngine()
            var time = 0.0
            var reps = 0
            func feed(_ body: BodyPose?, frames: Int) {
                for _ in 0..<frames {
                    time += 0.1
                    if engine.consume(body, movement: action, at: time) { reps += 1 }
                }
            }
            feed(pose(action), frames: 40)
            precondition(reps == 0, "Starting raised cannot earn a rep")
            feed(pose(), frames: 6)
            feed(pose(action), frames: 30)
            precondition(reps == 0, "Holding a target cannot earn a rep")
            feed(pose(), frames: 6)
            precondition(reps == 1, "Full cycle earns exactly one rep")
            feed(pose(action), frames: 4)
            feed(nil, frames: 1)
            feed(pose(action), frames: 20)
            feed(pose(), frames: 6)
            precondition(reps == 1, "Occlusion cancels unfinished cycle")
            feed(pose(action), frames: 4)
            time += 4
            feed(pose(action), frames: 20)
            feed(pose(), frames: 6)
            precondition(reps == 1, "Frame interruption cannot complete a hold")
        }

        let session = MovementSession()
        session.plannedSets = 2
        var coins = 0
        session.start { coins += 5 }
        var time = 0.0
        func feed(_ body: BodyPose?, frames: Int = 12) {
            for _ in 0..<frames { time += 0.1; session.receive(body, at: time) }
        }
        for group in 1...2 {
            for action in Movement.allCases {
                feed(pose())
                for _ in 0..<3 { feed(pose(action)); feed(pose()) }
            }
            precondition(coins == group * 5, "Exactly 5 coins per full set")
        }
        precondition(session.finished && session.progress == 1 && coins == 10)
        feed(pose(.reach), frames: 100)
        session.start { coins += 100 }
        precondition(coins == 10, "Finished session cannot credit twice")

        let partial = MovementSession()
        partial.selected = [.reach]
        partial.start { coins += 5 }
        for i in 1...10 { partial.receive(pose(), at: Double(i) / 10) }
        partial.togglePause()
        for i in 11...50 { partial.receive(pose(.reach), at: Double(i) / 10) }
        precondition(partial.repetitions == 0 && coins == 10, "Pause and partial sets earn nothing")
        print("Movement checks passed: geometry, cycles, occlusion, frame gaps, set rewards, pause, duplicate credit.")
    }
}
