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
