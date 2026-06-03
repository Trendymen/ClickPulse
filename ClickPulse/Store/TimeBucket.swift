import Foundation

struct TimeBucket: Equatable {
    let hourTimestamp: Int   // 本地墙钟整点对应的 epoch 秒
    let localHour: Int       // 0–23
    let localWeekday: Int    // 周一=1 … 周日=7

    static func current(date: Date = Date(), calendar: Calendar = .current) -> TimeBucket {
        let comps = calendar.dateComponents([.year, .month, .day, .hour, .weekday], from: date)
        let startOfHour = calendar.date(from: DateComponents(
            year: comps.year, month: comps.month, day: comps.day, hour: comps.hour))!
        let mondayBased = ((comps.weekday! + 5) % 7) + 1   // Calendar 周日=1…周六=7 → 周一=1…周日=7
        return TimeBucket(
            hourTimestamp: Int(startOfHour.timeIntervalSince1970),
            localHour: comps.hour!,
            localWeekday: mondayBased)
    }

    static func startOfHour(date: Date = Date(), calendar: Calendar = .current) -> Int {
        Int(calendar.dateInterval(of: .hour, for: date)!.start.timeIntervalSince1970)
    }
    static func startOfDay(date: Date = Date(), calendar: Calendar = .current) -> Int {
        Int(calendar.startOfDay(for: date).timeIntervalSince1970)
    }
    static func startOfWeek(date: Date = Date(), calendar: Calendar = .current) -> Int {
        Int(calendar.dateInterval(of: .weekOfYear, for: date)!.start.timeIntervalSince1970)
    }
    static func startOfMonth(date: Date = Date(), calendar: Calendar = .current) -> Int {
        Int(calendar.dateInterval(of: .month, for: date)!.start.timeIntervalSince1970)
    }
}
