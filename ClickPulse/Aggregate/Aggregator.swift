import Foundation

/// 把内存计数定时落库；翻篇用 drain(swap)。
/// 误差：flush 间隔(默认5s)内跨整点的点击会归到上一小时桶，最多一个间隔的点击、仅整点边界一次——对统计无实质影响。
final class Aggregator {
    private let counter: ClickCounter
    private let store: ClickStore
    private var lastBucket: TimeBucket
    private var timer: Timer?
    var onFlush: (() -> Void)?

    init(counter: ClickCounter, store: ClickStore) {
        self.counter = counter
        self.store = store
        self.lastBucket = TimeBucket.current(calendar: .appCalendar)
    }

    func start(interval: TimeInterval = 5) {
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.flush()
        }
    }

    func stop() { timer?.invalidate(); timer = nil }

    /// 退出/休眠前也应主动调用，确保不丢内存计数
    func flush() {
        let snap = counter.drain()
        for (button, n) in snap where n != 0 {
            try? store.add(bucket: lastBucket, button: button, delta: n)
        }
        lastBucket = TimeBucket.current(calendar: .appCalendar)
        onFlush?()
    }
}
