import Foundation

/// 临时调试输出：仅当环境变量 ENT303_DEBUG 存在时写 stderr。
enum Debug {
    static let enabled = ProcessInfo.processInfo.environment["ENT303_DEBUG"] != nil

    static func log(_ message: String) {
        guard enabled else { return }
        FileHandle.standardError.write(Data(("DBG " + message + "\n").utf8))
    }
}
