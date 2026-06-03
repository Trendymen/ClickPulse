import Foundation
extension Calendar {
    /// 应用统一日历：本地时区 + 周一为一周起点
    static var appCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone.current
        c.firstWeekday = 2
        return c
    }
}
