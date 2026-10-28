import Foundation

/// 一条"该起来动动了"的建议。
struct Suggestion: Identifiable, Equatable {
    let id = UUID()
    let icon: String      // SF Symbol 名
    let title: String
    let detail: String
}

enum Suggestions {
    static let all: [Suggestion] = [
        Suggestion(icon: "figure.walk",
                   title: "站起来走两步",
                   detail: "走到窗边或走廊，来回一趟就够。"),
        Suggestion(icon: "cup.and.saucer.fill",
                   title: "去倒杯水",
                   detail: "顺手把水喝完，别让杯子一直空着。"),
        Suggestion(icon: "eye",
                   title: "让眼睛歇 20 秒",
                   detail: "看向 6 米外的远处，别盯屏幕。"),
        Suggestion(icon: "figure.cooldown",
                   title: "拉伸一下肩颈",
                   detail: "头慢慢向左转、向右转，各停 5 秒。"),
        Suggestion(icon: "figure.arms.open",
                   title: "扩胸 + 深呼吸",
                   detail: "双手向后张开，吸气 4 秒，慢慢呼出。"),
        Suggestion(icon: "stairs",
                   title: "上下两层楼",
                   detail: "不走远，楼梯间来回一次就能回血。"),
        Suggestion(icon: "figure.stand",
                   title: "站着接个电话",
                   detail: "如果有电话要打，站着说完再坐下。"),
        Suggestion(icon: "drop.fill",
                   title: "喝口水再回来",
                   detail: "身体缺水时，注意力掉得比你想的快。"),
        Suggestion(icon: "figure.wave",
                   title: "手腕绕圈",
                   detail: "转 10 圈，反向再 10 圈，缓解鼠标手。"),
        Suggestion(icon: "sun.max.fill",
                   title: "晒 1 分钟太阳",
                   detail: "拉开窗帘，让自然光进来。"),
        Suggestion(icon: "lungs.fill",
                   title: "做 3 次深呼吸",
                   detail: "吸满、停 2 秒、缓慢吐完。"),
        Suggestion(icon: "figure.mind.and.body",
                   title: "靠墙站 30 秒",
                   detail: "后脑、肩胛、臀部贴墙，矫正含胸。")
    ]

    /// 随机取一条，尽量不跟刚弹过的那条重复。
    static func random(excluding previousTitle: String?) -> Suggestion {
        let pool = all.filter { $0.title != previousTitle }
        return (pool.isEmpty ? all : pool).randomElement()!
    }
}
