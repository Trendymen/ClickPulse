import XCTest
import GRDB
@testable import ClickPulse

final class ClickStoreSchemaTests: XCTestCase {
    private func tempURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cp-\(UUID().uuidString).sqlite")
    }

    func test_migrationCreatesTablesAndSetsVersion() throws {
        let url = tempURL()
        let store = try ClickStore(path: url)
        let exists = try store.dbQueue.read { db in
            try db.tableExists("click_hourly") && db.tableExists("meta")
        }
        XCTAssertTrue(exists)
        let version = try store.dbQueue.read { db in
            try Int.fetchOne(db, sql: "PRAGMA user_version") ?? -1
        }
        XCTAssertEqual(version, 1)
    }

    func test_openingTwiceIsIdempotent() throws {
        let url = tempURL()
        _ = try ClickStore(path: url)
        XCTAssertNoThrow(try ClickStore(path: url))
    }
}
