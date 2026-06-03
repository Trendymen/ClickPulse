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

    // 实时 bump 节流：累积增量，~200ms 合并一次刷新，避免每次点击即时重渲染（消除切筛选时的闪烁，也更平滑）
    @ObservationIgnored private var pending: [MouseButton: Int] = [:]
    @ObservationIgnored private var flushScheduled = false

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

    /// 实时乐观更新：点击计入 pending，~200ms 合并刷新一次（保留全部计数，仅合并 UI 刷新）。
    /// 定时 refresh 用 DB 值校正。节流让「点面板切筛选」的那次点击不会赶在切换前 +1 渲染，消除闪烁。
    func bump(_ button: MouseButton) {
        pending[button, default: 0] += 1
        guard !flushScheduled else { return }
        flushScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.flushPending()
        }
    }

    private func flushPending() {
        flushScheduled = false
        guard !pending.isEmpty else { return }
        let inc = pending
        pending.removeAll()
        var s = snapshot
        for (b, n) in inc {
            s.hour += n;  s.hourBy[b, default: 0]  += n
            s.day += n;   s.dayBy[b, default: 0]   += n
            s.week += n;  s.weekBy[b, default: 0]  += n
            s.month += n; s.monthBy[b, default: 0] += n
            s.total += n; s.byButton[b, default: 0] += n
        }
        snapshot = s
    }
}
