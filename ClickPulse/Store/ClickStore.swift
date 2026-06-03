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

    /// 每个小时桶的总点击（所有按键合计），按 hour_ts 升序。供趋势图在 Swift 端按「本地日」聚合，
    /// 避免 dailyTrend 用 86400 取整造成的 UTC 日界偏移（东八区会落在本地 08:00）。
    func hourlyTotals(since hourTs: Int) throws -> [(hour: Int, count: Int)] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql:
                "SELECT hour_ts, SUM(count) AS c FROM click_hourly WHERE hour_ts >= ? GROUP BY hour_ts ORDER BY hour_ts ASC",
                arguments: [hourTs])
            return rows.map { (hour: $0["hour_ts"], count: $0["c"]) }
        }
    }
}

extension ClickStore {
    func sum(since hourTs: Int) throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(db, sql:
                "SELECT COALESCE(SUM(count),0) FROM click_hourly WHERE hour_ts >= ?",
                arguments: [hourTs]) ?? 0
        }
    }

    /// 返回 7×24 矩阵：grid[weekday-1][hour] = 累计点击（含所有按键）
    func heatmap() throws -> [[Int]] {
        var grid = Array(repeating: Array(repeating: 0, count: 24), count: 7)
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT local_weekday AS w, local_hour AS h, SUM(count) AS c
                FROM click_hourly GROUP BY local_weekday, local_hour
                """)
            for row in rows {
                let w: Int = row["w"], h: Int = row["h"], c: Int = row["c"]
                if (1...7).contains(w), (0...23).contains(h) { grid[w - 1][h] = c }
            }
        }
        return grid
    }

    /// 近段每天总点击，返回按 day epoch 升序的 (dayStartTs, count)（趋势近似日界用 86400 取整）
    func dailyTrend(sinceDayStart: Int) throws -> [(day: Int, count: Int)] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT (hour_ts - (hour_ts % 86400)) AS day, SUM(count) AS c
                FROM click_hourly WHERE hour_ts >= ?
                GROUP BY day ORDER BY day ASC
                """, arguments: [sinceDayStart])
            return rows.map { (day: $0["day"], count: $0["c"]) }
        }
    }
}

extension ClickStore {
    /// 每个小时桶一行，按键聚成 HourRow（供导出）
    func allRows() throws -> [HourRow] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT hour_ts, local_hour, local_weekday, button, count
                FROM click_hourly ORDER BY hour_ts ASC
                """)
            var byBucket: [Int: (Int, Int, [MouseButton: Int])] = [:]
            for r in rows {
                let ts: Int = r["hour_ts"]
                var entry = byBucket[ts] ?? (r["local_hour"], r["local_weekday"], [:])
                if let b = MouseButton(rawValue: r["button"]) { entry.2[b] = r["count"] }
                byBucket[ts] = entry
            }
            return byBucket.keys.sorted().map { ts in
                let e = byBucket[ts]!
                return HourRow(hourTs: ts, localHour: e.0, localWeekday: e.1, counts: e.2)
            }
        }
    }
}
