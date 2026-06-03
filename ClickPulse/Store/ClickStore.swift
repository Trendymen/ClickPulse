import GRDB
import Foundation

final class ClickStore {
    let dbQueue: DatabaseQueue

    init(path: URL) throws {
        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        var config = Configuration()
        config.prepareDatabase { db in try db.execute(sql: "PRAGMA journal_mode = WAL;") }
        dbQueue = try DatabaseQueue(path: path.path, configuration: config)
        try Migrations.makeMigrator().migrate(dbQueue)
        try dbQueue.write { db in try db.execute(sql: "PRAGMA user_version = 1;") }
    }
}

extension ClickStore {
    func add(bucket: TimeBucket, button: MouseButton, delta: Int) throws {
        guard delta != 0 else { return }
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO click_hourly (hour_ts, local_hour, local_weekday, button, count)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(hour_ts, button) DO UPDATE SET count = count + excluded.count;
                """,
                arguments: [bucket.hourTimestamp, bucket.localHour, bucket.localWeekday, button.rawValue, delta])
        }
    }

    func total() throws -> Int {
        try dbQueue.read { db in try Int.fetchOne(db, sql: "SELECT COALESCE(SUM(count),0) FROM click_hourly") ?? 0 }
    }

    func sumByButton(since hourTs: Int) throws -> [MouseButton: Int] {
        try dbQueue.read { db in
            var result: [MouseButton: Int] = [:]
            let rows = try Row.fetchAll(db, sql:
                "SELECT button, SUM(count) AS c FROM click_hourly WHERE hour_ts >= ? GROUP BY button",
                arguments: [hourTs])
            for row in rows {
                if let b = MouseButton(rawValue: row["button"]) { result[b] = row["c"] }
            }
            return result
        }
    }
}
