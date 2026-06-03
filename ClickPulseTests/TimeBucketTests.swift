import XCTest
@testable import ClickPulse

final class TimeBucketTests: XCTestCase {
    private func cal(_ tzID: String = "Asia/Shanghai") -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: tzID)!
        c.firstWeekday = 2   // 周一
        return c
    }

    func test_localHourAndWeekday_areLocal_notUTC() {
        var comp = DateComponents()
        comp.year = 2026; comp.month = 6; comp.day = 1; comp.hour = 14; comp.minute = 30
        let date = cal().date(from: comp)!
        let b = TimeBucket.current(date: date, calendar: cal())
        XCTAssertEqual(b.localHour, 14)
        XCTAssertEqual(b.localWeekday, 1)     // 2026-06-01 是周一 = 1
    }

    func test_sunday_mapsTo7() {
        var comp = DateComponents()
        comp.year = 2026; comp.month = 6; comp.day = 7; comp.hour = 9   // 2026-06-07 周日
        let date = cal().date(from: comp)!
        XCTAssertEqual(TimeBucket.current(date: date, calendar: cal()).localWeekday, 7)
    }

    func test_hourTimestamp_isStartOfLocalHour() {
        var comp = DateComponents()
        comp.year = 2026; comp.month = 6; comp.day = 1; comp.hour = 14; comp.minute = 59; comp.second = 59
        let date = cal().date(from: comp)!
        let b = TimeBucket.current(date: date, calendar: cal())
        let expected = Int(cal().date(bySettingHour: 14, minute: 0, second: 0, of: date)!.timeIntervalSince1970)
        XCTAssertEqual(b.hourTimestamp, expected)
    }

    func test_startOfWeek_isMonday() {
        var comp = DateComponents()
        comp.year = 2026; comp.month = 6; comp.day = 3   // 周三
        let date = cal().date(from: comp)!
        let monday = TimeBucket.startOfWeek(date: date, calendar: cal())
        var mComp = DateComponents(); mComp.year = 2026; mComp.month = 6; mComp.day = 1
        XCTAssertEqual(monday, Int(cal().date(from: mComp)!.timeIntervalSince1970))
    }
}
