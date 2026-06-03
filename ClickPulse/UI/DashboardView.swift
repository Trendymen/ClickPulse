import SwiftUI

private enum ButtonFilter: String, CaseIterable { case 合计, 左键, 右键, 中键, 其它 }

struct DashboardView: View {
    @Bindable var stats: StatsProvider
    @State private var filter: ButtonFilter = .合计

    private func value(_ total: Int, _ by: [MouseButton: Int]) -> Int {
        switch filter {
        case .合计: return total
        case .左键: return by[.left] ?? 0
        case .右键: return by[.right] ?? 0
        case .中键: return by[.middle] ?? 0
        case .其它: return by[.other] ?? 0
        }
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
                cell("时", value(stats.snapshot.hour,  stats.snapshot.hourBy))
                cell("日", value(stats.snapshot.day,   stats.snapshot.dayBy))
                cell("周", value(stats.snapshot.week,  stats.snapshot.weekBy))
                cell("月", value(stats.snapshot.month, stats.snapshot.monthBy))
                cell("总", value(stats.snapshot.total, stats.snapshot.byButton))
            }
        }
    }

    private func cell(_ label: String, _ n: Int) -> some View {
        VStack(spacing: 2) {
            Text(ClickFormat.display(n))
                .font(.title3).monospacedDigit().fontWeight(.semibold)
                .lineLimit(1)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
    }
}
