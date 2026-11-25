import Foundation
import Combine

/// 跟练累计数据：用于"完成一次"后的小结卡片，体现产品价值。
struct MovementStats: Codable, Equatable {
    var totalReps = 0
    var byAction: [String: Int] = [:]
    var days: [String] = []          // yyyy-MM-dd
    var avoidedSeconds = 0           // 累计"没有坐着"的时间

    var dayCount: Int { days.count }

    var avoidedText: String {
        let minutes = avoidedSeconds / 60
        if minutes < 60 { return Lang.t("\(minutes) 分钟", "\(minutes)m") }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? Lang.t("\(h) 小时", "\(h)h") : Lang.t("\(h) 小时 \(m) 分", "\(h)h \(m)m")
    }
}

/// 一次动作完成后的简明报告
struct MovementReport: Equatable {
    let action: String
    let gained: Int
    let dayCount: Int
    let totalReps: Int
    let avoidedText: String
    let isNewDay: Bool
}

enum MovementStatsStore {
    private static let key = "RISE_MovementStats_v1"

    static func load() -> MovementStats {
        guard let data = UserDefaults.standard.data(forKey: key),
              let value = try? JSONDecoder().decode(MovementStats.self, from: data)
        else { return MovementStats() }
        return value
    }

    static func save(_ stats: MovementStats) {
        guard let data = try? JSONEncoder().encode(stats) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func todayKey(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
