import os

final class ClickCounter {
    private var counts: [MouseButton: Int] = [:]
    private let lock = OSAllocatedUnfairLock()

    func increment(_ button: MouseButton) {
        lock.withLock { counts[button, default: 0] += 1 }
    }

    /// 原子取出当前计数并清零（整点翻篇 / flush 用）
    func drain() -> [MouseButton: Int] {
        lock.withLock {
            let snapshot = counts
            counts = [:]
            return snapshot
        }
    }
}
