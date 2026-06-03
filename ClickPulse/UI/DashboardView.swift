import SwiftUI

private enum ButtonFilter: String, CaseIterable { case 合计, 左键, 右键, 中键, 其它 }

struct DashboardView: View {
    @Bindable var stats: StatsProvider
    @State private var filter: ButtonFilter = .合计

    private func value(_ total: Int) -> Int {
        switch filter {
        case .合计: return total
        case .左键: return scaled(total, .left)
        case .右键: return scaled(total, .right)
        case .中键: return scaled(total, .middle)
        case .其它: return scaled(total, .other)
        }
    }
    private func scaled(_ total: Int, _ b: MouseButton) -> Int {
        let all = stats.snapshot.byButton.values.reduce(0, +)
        guard all > 0 else { return 0 }
        return Int((Double(total) * Double(stats.snapshot.byButton[b] ?? 0) / Double(all)).rounded())
    }

    private var filters: [ButtonFilter] {
        var fs: [ButtonFilter] = [.合计, .左键, .右键, .中键]
        if (stats.snapshot.byButton[.other] ?? 0) > 0 { fs.append(.其它) }
        return fs
    }

    var body: some View {
        VStack(spacing: 8) {
            Picker("", selection: $filter) {
                ForEach(filters, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            HStack(spacing: 0) {
                cell("时", value(stats.snapshot.hour))
                cell("日", value(stats.snapshot.day))
                cell("周", value(stats.snapshot.week))
                cell("月", value(stats.snapshot.month))
                cell("总", value(stats.snapshot.total))
            }
        }
    }

    private func cell(_ label: String, _ n: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(n)").font(.title3).monospacedDigit().fontWeight(.semibold)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
    }
}
