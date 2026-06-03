import Foundation
import Observation

struct StatsSnapshot: Equatable {
    var hour = 0, day = 0, week = 0, month = 0, total = 0
    var byButton: [MouseButton: Int] = [:]   // 全局（=总）分按键，沿用旧字段
    // 各时段的真实分按键计数（替代过去按全局比例摊派的估算）
    var hourBy: [MouseButton: Int] = [:]
    var dayBy: [MouseButton: Int] = [:]
    var weekBy: [MouseButton: Int] = [:]
    var monthBy: [MouseButton: Int] = [:]
}

@Observable
final class StatsProvider {
    private let store: ClickStore
    var snapshot = StatsSnapshot()
    var heatmap: [[Int]] = Array(repeating: Array(repeating: 0, count: 24), count: 7)

    init(store: ClickStore) { self.store = store }

    func refresh(calendar: Calendar = .appCalendar, now: Date = Date()) {
        var s = StatsSnapshot()
        // 每个时段都取真实的分按键计数；合计 = 各按键之和（省去单独的 sum 查询）
        func bucket(_ since: Int) -> (Int, [MouseButton: Int]) {
            let by = (try? store.sumByButton(since: since)) ?? [:]
            return (by.values.reduce(0, +), by)
        }
        (s.hour,  s.hourBy)   = bucket(TimeBucket.startOfHour(date: now, calendar: calendar))
        (s.day,   s.dayBy)    = bucket(TimeBucket.startOfDay(date: now, calendar: calendar))
        (s.week,  s.weekBy)   = bucket(TimeBucket.startOfWeek(date: now, calendar: calendar))
        (s.month, s.monthBy)  = bucket(TimeBucket.startOfMonth(date: now, calendar: calendar))
        (s.total, s.byButton) = bucket(0)
        snapshot = s
        heatmap = (try? store.heatmap()) ?? heatmap
    }

    /// 实时乐观更新：每次点击立即 +1（面板点击即跳，不等定时落库）；定时 refresh 会用 DB 值校正
    func bump(_ button: MouseButton) {
        snapshot.hour += 1;  snapshot.hourBy[button, default: 0]  += 1
        snapshot.day += 1;   snapshot.dayBy[button, default: 0]   += 1
        snapshot.week += 1;  snapshot.weekBy[button, default: 0]  += 1
        snapshot.month += 1; snapshot.monthBy[button, default: 0] += 1
        snapshot.total += 1; snapshot.byButton[button, default: 0] += 1
    }
}
