import XCTest
@testable import ClickPulse

final class ExportServiceTests: XCTestCase {
    private let rows = [
        HourRow(hourTs: 1_780_000_000, localHour: 14, localWeekday: 1,
                counts: [.left: 10, .right: 2, .middle: 1, .other: 0])
    ]

    func test_csvHasHeaderAndRow() {
        let csv = ExportService.csv(rows: rows)
        let lines = csv.split(separator: "\n")
        XCTAssertEqual(lines.first, "hour_iso8601,local_hour,local_weekday,left,right,middle,other")
        XCTAssertTrue(lines[1].hasSuffix(",14,1,10,2,1,0"))
    }

    func test_jsonRoundTrips() throws {
        let data = try ExportService.json(rows: rows, timezone: "Asia/Shanghai", schemaVersion: 1)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(obj["schema_version"] as? Int, 1)
        XCTAssertEqual(obj["timezone"] as? String, "Asia/Shanghai")
        XCTAssertEqual((obj["records"] as? [[String: Any]])?.count, 1)
    }
}
