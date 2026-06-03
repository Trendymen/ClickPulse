import XCTest
@testable import ClickPulse

final class ClickStoreAllRowsTests: XCTestCase {
    func test_allRowsGroupsButtonsPerBucket() throws {
        let store = try ClickStore(path: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cp-\(UUID().uuidString).sqlite"))
        let b = TimeBucket(hourTimestamp: 1_780_000_000, localHour: 14, localWeekday: 1)
        try store.add(bucket: b, button: .left, delta: 10)
        try store.add(bucket: b, button: .right, delta: 2)
        let rows = try store.allRows()
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].c(.left), 10)
        XCTAssertEqual(rows[0].c(.right), 2)
        XCTAssertEqual(rows[0].localHour, 14)
    }
}
