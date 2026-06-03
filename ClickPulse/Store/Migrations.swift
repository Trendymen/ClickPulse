import GRDB

enum Migrations {
    static func makeMigrator() -> DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            try db.execute(sql: """
                CREATE TABLE click_hourly (
                    hour_ts       INTEGER NOT NULL,
                    local_hour    INTEGER NOT NULL,
                    local_weekday INTEGER NOT NULL,
                    button        INTEGER NOT NULL,
                    count         INTEGER NOT NULL DEFAULT 0,
                    PRIMARY KEY (hour_ts, button)
                );
            """)
            try db.execute(sql: "CREATE INDEX idx_click_hour ON click_hourly(hour_ts);")
            try db.execute(sql: "CREATE INDEX idx_click_local ON click_hourly(local_weekday, local_hour);")
            try db.execute(sql: "CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT);")
            try db.execute(sql: "PRAGMA user_version = 1;")
        }
        return m
    }
}
