import SwiftUI
import Charts

struct TrendView: View {
    let store: ClickStore
    @State private var points: [TrendPoint] = []

    struct TrendPoint: Identifiable {
        let id = UUID()
        let day: Date
        let count: Int
    }

    var body: some View {
        Group {
            if points.allSatisfy({ $0.count == 0 }) {
                VStack { Spacer(); Text("开始点击后这里会出现统计").foregroundStyle(.secondary); Spacer() }
            } else {
                Chart(points) { p in
                    LineMark(x: .value("日期", p.day), y: .value("点击", p.count))
                    PointMark(x: .value("日期", p.day), y: .value("点击", p.count))
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: max(1, (points.count + 5) / 6))) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month().day())
                    }
                }
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        let cal = Calendar.appCalendar
        let since = TimeBucket.startOfDay(date: Date().addingTimeInterval(-30 * 86400), calendar: cal)
        let rows = (try? store.hourlyTotals(since: since)) ?? []
        // 在 Swift 端按「本地日」聚合，数据点落在本地 0 点，与横轴按天刻度对齐
        var byDay: [Date: Int] = [:]
        for r in rows {
            let day = cal.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(r.hour)))
            byDay[day, default: 0] += r.count
        }
        points = byDay.sorted { $0.key < $1.key }.map { TrendPoint(day: $0.key, count: $0.value) }
    }
}
