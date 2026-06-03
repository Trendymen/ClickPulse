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
                }
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        let cal = Calendar.appCalendar
        let since = TimeBucket.startOfDay(date: Date().addingTimeInterval(-30 * 86400), calendar: cal)
        let raw = (try? store.dailyTrend(sinceDayStart: since)) ?? []
        points = raw.map { TrendPoint(day: Date(timeIntervalSince1970: TimeInterval($0.day)), count: $0.count) }
    }
}
