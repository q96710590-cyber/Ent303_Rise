import Foundation

/// 全局语言开关。
/// 视图层用 `state.t(...)`；模型层（Session / Engine / Camera）没有 AppState，
/// 统一走这里，AppState 的 isEnglish 变化时会同步过来。
enum Lang {
    static var isEnglish = CommandLine.arguments.contains("--demo-english")
    static func t(_ zh: String, _ en: String) -> String { isEnglish ? en : zh }
}
