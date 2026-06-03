import XCTest
@testable import ClickPulse

final class ClickStoreQueryTests: XCTestCase {
    private func makeStore() throws -> ClickStore {
        try ClickStore(path: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cp-\(UUID().uuidString).sqlite"))
    }

    func test_sumSinceCutoff() throws {
        let store = try makeStore()
        try store.add(bucket: TimeBucket(hourTimestamp: 100, localHour: 0, localWeekday: 1), button: .left, delta: 5)
        try store.add(bucket: TimeBucket(hourTimestamp: 200, localHour: 1, localWeekday: 1), button: .left, delta: 7)
        XCTAssertEqual(try store.sum(since: 150), 7)
        XCTAssertEqual(try store.sum(since: 0), 12)
    }

    func test_heatmapBucketsByLocalWeekdayHour() throws {
        let store = try makeStore()
        try store.add(bucket: TimeBucket(hourTimestamp: 1, localHour: 14, localWeekday: 1), button: .left, delta: 3)
        try store.add(bucket: TimeBucket(hourTimestamp: 2, localHour: 9, localWeekday: 7), button: .right, delta: 2)
        let grid = try store.heatmap()
        XCTAssertEqual(grid.count, 7)
        XCTAssertEqual(grid[0].count, 24)
        XCTAssertEqual(grid[0][14], 3)
        XCTAssertEqual(grid[6][9], 2)
        XCTAssertEqual(grid[0][9], 0)
    }
}
