import XCTest
@testable import ClickPulse

final class ClickStoreWriteTests: XCTestCase {
    private func makeStore() throws -> ClickStore {
        try ClickStore(path: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cp-\(UUID().uuidString).sqlite"))
    }
    private let bucket = TimeBucket(hourTimestamp: 1_780_000_000, localHour: 14, localWeekday: 1)

    func test_addAccumulatesSameBucketButton() throws {
        let store = try makeStore()
        try store.add(bucket: bucket, button: .left, delta: 3)
        try store.add(bucket: bucket, button: .left, delta: 2)
        XCTAssertEqual(try store.total(), 5)
    }

    func test_differentButtonsAreSeparateRows() throws {
        let store = try makeStore()
        try store.add(bucket: bucket, button: .left, delta: 4)
        try store.add(bucket: bucket, button: .right, delta: 1)
        XCTAssertEqual(try store.total(), 5)
        XCTAssertEqual(try store.sumByButton(since: 0)[.left], 4)
        XCTAssertEqual(try store.sumByButton(since: 0)[.right], 1)
    }
}
