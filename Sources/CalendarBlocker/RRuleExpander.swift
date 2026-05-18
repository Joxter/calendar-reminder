import Foundation

// Minimal RFC 5545 RRULE expander covering the patterns Google Calendar produces.
// Supported: FREQ (DAILY/WEEKLY/MONTHLY/YEARLY), INTERVAL, BYDAY, BYMONTHDAY, UNTIL, COUNT.
enum RRuleExpander {

    // Returns occurrence start-times that fall within `range`, respecting UNTIL/COUNT.
    static func occurrences(dtstart: Date, rrule: String, in range: DateInterval) -> [Date] {
        guard let rule = parseRule(rrule) else { return [] }
        guard dtstart <= range.end else { return [] }
        if let u = rule.until, u < range.start { return [] }

        switch rule.freq {
        case .daily:   return dailyOccs(dtstart, rule, range)
        case .weekly:  return weeklyOccs(dtstart, rule, range)
        case .monthly: return monthlyOccs(dtstart, rule, range)
        case .yearly:  return yearlyOccs(dtstart, rule, range)
        }
    }

    // MARK: - Generators

    private static func dailyOccs(_ dtstart: Date, _ r: Rule, _ range: DateInterval) -> [Date] {
        var results: [Date] = []
        var n = 0
        var cur = dtstart
        while cur <= range.end {
            if let u = r.until, cur > u { break }
            if let c = r.count, n >= c { break }
            n += 1
            if cur >= range.start { results.append(cur) }
            cur = cal.date(byAdding: .day, value: r.interval, to: cur)!
        }
        return results
    }

    private static func weeklyOccs(_ dtstart: Date, _ r: Rule, _ range: DateInterval) -> [Date] {
        // Weekdays this rule fires on (Calendar.weekday: 1=Sun … 7=Sat)
        let weekdays = r.byDay.isEmpty
            ? [cal.component(.weekday, from: dtstart)]
            : r.byDay.compactMap { $0.n == nil ? $0.weekday : nil }

        let time = cal.dateComponents([.hour, .minute, .second], from: dtstart)
        // Anchor to dtstart's week (start-of-week in current locale)
        let dtWeek = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: dtstart))!

        var results: [Date] = []
        var n = 0
        var week = dtWeek
        while week <= range.end {
            for wd in weekdays.sorted() {
                var c = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: week)
                c.weekday = wd; c.hour = time.hour; c.minute = time.minute; c.second = time.second
                guard let occ = cal.date(from: c), occ >= dtstart else { continue }
                if let u = r.until, occ > u { return results }
                if let c2 = r.count, n >= c2 { return results }
                n += 1
                if occ >= range.start && occ < range.end { results.append(occ) }
            }
            week = cal.date(byAdding: .weekOfYear, value: r.interval, to: week)!
        }
        return results
    }

    private static func monthlyOccs(_ dtstart: Date, _ r: Rule, _ range: DateInterval) -> [Date] {
        let time = cal.dateComponents([.hour, .minute, .second], from: dtstart)
        let dtMonth = cal.date(from: cal.dateComponents([.year, .month], from: dtstart))!

        var results: [Date] = []
        var n = 0
        var month = dtMonth
        while month <= range.end {
            for occ in monthCandidates(month, r, time, dtstart).sorted() {
                guard occ >= dtstart else { continue }
                if let u = r.until, occ > u { return results }
                if let c = r.count, n >= c { return results }
                n += 1
                if occ >= range.start && occ < range.end { results.append(occ) }
            }
            month = cal.date(byAdding: .month, value: r.interval, to: month)!
        }
        return results
    }

    private static func yearlyOccs(_ dtstart: Date, _ r: Rule, _ range: DateInterval) -> [Date] {
        let time = cal.dateComponents([.hour, .minute, .second], from: dtstart)
        let md   = cal.dateComponents([.month, .day], from: dtstart)
        let endYear = cal.component(.year, from: range.end)

        var results: [Date] = []
        var n = 0
        var year = cal.component(.year, from: dtstart)
        while year <= endYear {
            var c = DateComponents()
            c.year = year; c.month = md.month; c.day = md.day
            c.hour = time.hour; c.minute = time.minute; c.second = time.second
            if let occ = cal.date(from: c), occ >= dtstart {
                if let u = r.until, occ > u { return results }
                if let ct = r.count, n >= ct { return results }
                n += 1
                if occ >= range.start && occ < range.end { results.append(occ) }
            }
            year += r.interval
        }
        return results
    }

    // Candidate occurrence dates within a given month for a MONTHLY rule.
    private static func monthCandidates(_ month: Date, _ r: Rule, _ time: DateComponents, _ dtstart: Date) -> [Date] {
        if !r.byDay.isEmpty {
            return r.byDay.compactMap { nthWeekday($0.n, $0.weekday, month, time) }
        }
        if !r.byMonthDay.isEmpty {
            return r.byMonthDay.compactMap { day -> Date? in
                var c = cal.dateComponents([.year, .month], from: month)
                c.day = day; c.hour = time.hour; c.minute = time.minute; c.second = time.second
                return cal.date(from: c)
            }
        }
        // Default: same day-of-month as dtstart
        var c = cal.dateComponents([.year, .month], from: month)
        c.day = cal.component(.day, from: dtstart)
        c.hour = time.hour; c.minute = time.minute; c.second = time.second
        return [cal.date(from: c)].compactMap { $0 }
    }

    // Returns the date of the n-th occurrence of `weekday` in the month of `month`.
    // n=1 → first, n=2 → second, n=-1 → last, nil → skip (handled upstream).
    private static func nthWeekday(_ n: Int?, _ weekday: Int, _ month: Date, _ time: DateComponents) -> Date? {
        guard let n else { return nil }
        if n > 0 {
            var c = cal.dateComponents([.year, .month], from: month)
            c.weekday = weekday; c.weekdayOrdinal = n
            c.hour = time.hour; c.minute = time.minute; c.second = time.second
            return cal.date(from: c)
        }
        // Negative ordinal: collect all then index from end
        var all: [Date] = []
        for ord in 1...5 {
            var c = cal.dateComponents([.year, .month], from: month)
            c.weekday = weekday; c.weekdayOrdinal = ord
            c.hour = time.hour; c.minute = time.minute; c.second = time.second
            if let d = cal.date(from: c), cal.isDate(d, equalTo: month, toGranularity: .month) {
                all.append(d)
            }
        }
        let idx = all.count + n  // n=-1 → last
        return idx >= 0 ? all[idx] : nil
    }

    // MARK: - Rule parsing

    private static let cal = Calendar.current

    private enum Freq { case daily, weekly, monthly, yearly }

    private struct Rule {
        var freq: Freq = .weekly
        var interval: Int = 1
        var byDay: [(n: Int?, weekday: Int)] = []
        var byMonthDay: [Int] = []
        var until: Date?
        var count: Int?
    }

    private static func parseRule(_ s: String) -> Rule? {
        var r = Rule()
        for part in s.components(separatedBy: ";") {
            let kv = part.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2 else { continue }
            switch kv[0] {
            case "FREQ":
                switch kv[1] {
                case "DAILY":   r.freq = .daily
                case "WEEKLY":  r.freq = .weekly
                case "MONTHLY": r.freq = .monthly
                case "YEARLY":  r.freq = .yearly
                default: return nil
                }
            case "INTERVAL":    r.interval = Int(kv[1]) ?? 1
            case "BYDAY":       r.byDay = kv[1].components(separatedBy: ",").compactMap(parseWeekday)
            case "BYMONTHDAY":  r.byMonthDay = kv[1].components(separatedBy: ",").compactMap(Int.init)
            case "UNTIL":       r.until = parseUntil(kv[1])
            case "COUNT":       r.count = Int(kv[1])
            default: break
            }
        }
        return r
    }

    // Parse "MO", "2MO", "-1FR" → (ordinal, Calendar.weekday)
    private static func parseWeekday(_ s: String) -> (n: Int?, weekday: Int)? {
        let map = ["SU":1,"MO":2,"TU":3,"WE":4,"TH":5,"FR":6,"SA":7]
        if let wd = map[s] { return (nil, wd) }
        guard s.count > 2 else { return nil }
        let tag = String(s.suffix(2))
        let prefix = String(s.prefix(s.count - 2))
        guard let wd = map[tag], let n = Int(prefix) else { return nil }
        return (n, wd)
    }

    private static func parseUntil(_ s: String) -> Date? {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        if s.hasSuffix("Z") {
            fmt.timeZone = TimeZone(identifier: "UTC")
            fmt.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        } else if s.count == 15 {
            fmt.timeZone = .current
            fmt.dateFormat = "yyyyMMdd'T'HHmmss"
        } else {
            fmt.timeZone = .current
            fmt.dateFormat = "yyyyMMdd"
        }
        return fmt.date(from: s)
    }
}
