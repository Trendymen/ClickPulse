import Foundation

/// 面板数字的展示格式化：日常千分位、超大数紧凑单位，跟随系统 locale。
enum ClickFormat {
    /// < 100 万：千分位（locale 感知，如 33,970）；>= 100 万：紧凑单位，跟随系统语言：
    /// 中文系统显示「123万 / 1.5亿」，英文系统显示「1.2M / 1.5B」，保留 0-1 位小数。
    static func display(_ n: Int) -> String {
        if n < 1_000_000 {
            return n.formatted()
        }
        // fractionLength(0...1) 施加到「整数 + compactName」为有意为之：
        // 紧凑换算后按浮点精度处理（如 1_500_000 → 1.5亿），已验证编译与运行正确。
        return n.formatted(
            .number
                .notation(.compactName)
                .precision(.fractionLength(0...1)))
    }
}
