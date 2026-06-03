import Foundation

struct HourRow {
    let hourTs: Int
    let localHour: Int
    let localWeekday: Int
    let counts: [MouseButton: Int]
    func c(_ b: MouseButton) -> Int { counts[b] ?? 0 }
}

enum ExportService {
    static func csv(rows: [HourRow]) -> String {
        var out = "hour_iso8601,local_hour,local_weekday,left,right,middle,other\n"
        let fmt = ISO8601DateFormatter()
        for r in rows {
            let iso = fmt.string(from: Date(timeIntervalSince1970: TimeInterval(r.hourTs)))
            out += "\(iso),\(r.localHour),\(r.localWeekday),\(r.c(.left)),\(r.c(.right)),\(r.c(.middle)),\(r.c(.other))\n"
        }
        return out
    }

    static func json(rows: [HourRow], timezone: String, schemaVersion: Int) throws -> Data {
        let fmt = ISO8601DateFormatter()
        let records: [[String: Any]] = rows.map { r in
            ["hour": fmt.string(from: Date(timeIntervalSince1970: TimeInterval(r.hourTs))),
             "local_hour": r.localHour, "local_weekday": r.localWeekday,
             "left": r.c(.left), "right": r.c(.right), "middle": r.c(.middle), "other": r.c(.other)]
        }
        let root: [String: Any] = [
            "exported_at": fmt.string(from: Date()),
            "timezone": timezone, "schema_version": schemaVersion, "records": records]
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }
}
