import SwiftUI

struct HeatmapView: View {
    let grid: [[Int]]   // [weekday0..6][hour0..23]
    private let weekdays = ["一","二","三","四","五","六","日"]

    private var maxVal: Int { grid.flatMap { $0 }.max() ?? 0 }
    private var hasData: Bool { maxVal > 0 }

    var body: some View {
        if !hasData {
            VStack { Spacer(); Text("开始点击后这里会出现统计").foregroundStyle(.secondary); Spacer() }
        } else {
            VStack(spacing: 2) {
                ForEach(0..<7, id: \.self) { w in
                    HStack(spacing: 2) {
                        Text(weekdays[w]).font(.caption2).frame(width: 14)
                        ForEach(0..<24, id: \.self) { h in cell(grid[w][h]) }
                    }
                }
                Text("颜色越深点击越多 · 横轴 0–23 时").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func cell(_ v: Int) -> some View {
        let intensity = maxVal > 0 ? Double(v) / Double(maxVal) : 0
        return RoundedRectangle(cornerRadius: 2)
            .fill(v == 0 ? Color.gray.opacity(0.12) : Color.accentColor.opacity(0.15 + 0.85 * intensity))
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
    }
}
