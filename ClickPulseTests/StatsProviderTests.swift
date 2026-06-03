import XCTest
@testable import ClickPulse

final class StatsProviderTests: XCTestCase {
    func test_refreshComputesFiveBuckets() throws {
        let store = try ClickStore(path: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cp-\(UUID().uuidString).sqlite"))
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        cal.firstWeekday = 2
        var comp = DateComponents(); comp.year = 2026; comp.month = 6; comp.day = 3; comp.hour = 10
        let now = cal.date(from: comp)!

        let hb = TimeBucket.current(date: now, calendar: cal)
        try store.add(bucket: hb, button: .left, delta: 5)

        let provider = StatsProvider(store: store)
        provider.refresh(calendar: cal, now: now)
        XCTAssertEqual(provider.snapshot.hour, 5)
        XCTAssertEqual(provider.snapshot.day, 5)
        XCTAssertEqual(provider.snapshot.total, 5)
        XCTAssertEqual(provider.snapshot.byButton[.left], 5)
    }
}
