import Foundation
import Observation

struct StatsSnapshot: Equatable {
    var hour = 0, day = 0, week = 0, month = 0, total = 0
    var byButton: [MouseButton: Int] = [:]
}

@Observable
final class StatsProvider {
    private let store: ClickStore
    var snapshot = StatsSnapshot()
    var heatmap: [[Int]] = Array(repeating: Array(repeating: 0, count: 24), count: 7)

    init(store: ClickStore) { self.store = store }

    func refresh(calendar: Calendar = .appCalendar, now: Date = Date()) {
        var s = StatsSnapshot()
        s.hour  = (try? store.sum(since: TimeBucket.startOfHour(date: now, calendar: calendar)))  ?? 0
        s.day   = (try? store.sum(since: TimeBucket.startOfDay(date: now, calendar: calendar)))   ?? 0
        s.week  = (try? store.sum(since: TimeBucket.startOfWeek(date: now, calendar: calendar)))  ?? 0
        s.month = (try? store.sum(since: TimeBucket.startOfMonth(date: now, calendar: calendar))) ?? 0
        s.total = (try? store.total()) ?? 0
        s.byButton = (try? store.sumByButton(since: 0)) ?? [:]
        snapshot = s
        heatmap = (try? store.heatmap()) ?? heatmap
    }
}
