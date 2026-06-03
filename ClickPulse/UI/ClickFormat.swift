import Foundation

/// 面板数字的展示格式化：日常千分位、超大数紧凑单位，跟随系统 locale。
enum ClickFormat {
    /// < 100 万：千分位（locale 感知，如 33,970）；>= 100 万：紧凑单位（123万 / 1.2亿 / 1.2M），保留 0-1 位小数。
    static func display(_ n: Int) -> String {
        if n < 1_000_000 {
            return n.formatted()
        }
        return n.formatted(
            .number
                .notation(.compactName)
                .precision(.fractionLength(0...1)))
    }
}
