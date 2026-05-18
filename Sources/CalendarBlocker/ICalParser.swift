import Foundation

struct CalEvent: Equatable {
    let title: String
    let start: Date
    let end: Date
    let uid: String?

    var startsInSeconds: TimeInterval { start.timeIntervalSince(Config.now) }
    var duration: TimeInterval { end.timeIntervalSince(start) }

    static func == (lhs: CalEvent, rhs: CalEvent) -> Bool {
        lhs.title == rhs.title && lhs.start == rhs.start
    }
}

enum ICalParser {
    private struct RawEvent {
        var title: String?
        var uid: String?
        var start: Date?
        var end: Date?
        var duration: TimeInterval?
        var rrule: String?
        var exdates: [Date] = []
    }

    // Parses iCal text and returns events whose start falls within `range`.
    // Recurring events (RRULE) are expanded; each occurrence becomes a CalEvent.
    static func parse(_ text: String, expandingIn range: DateInterval) -> [CalEvent] {
        let unfolded = unfold(text)
        var result: [CalEvent] = []
        var raw = RawEvent()
        var inEvent = false

        for line in unfolded.components(separatedBy: "\n") {
            let line = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }

            switch line {
            case "BEGIN:VEVENT":
                inEvent = true
                raw = RawEvent()
            case "END:VEVENT":
                if inEvent { result += expand(raw, in: range) }
                inEvent = false
            default:
                guard inEvent else { continue }
                // Key is everything before the first ':' or ';'
                let key = String(line.prefix(while: { $0 != ":" && $0 != ";" }))
                switch key {
                case "SUMMARY":  raw.title    = afterColon(line)
                case "UID":      raw.uid      = afterColon(line)
                case "DTSTART":  raw.start    = parseDate(line)
                case "DTEND":    raw.end      = parseDate(line)
                case "DURATION": raw.duration = parseDuration(afterColon(line))
                case "RRULE":    raw.rrule    = afterColon(line)
                case "EXDATE":   raw.exdates += parseDates(line)
                default: break
                }
            }
        }
        return result.sorted { $0.start < $1.start }
    }

    // MARK: - Expansion

    private static func expand(_ raw: RawEvent, in range: DateInterval) -> [CalEvent] {
        guard let title = raw.title, let dtstart = raw.start else { return [] }

        let eventDuration: TimeInterval
        if let end = raw.end {
            eventDuration = end.timeIntervalSince(dtstart)
        } else if let dur = raw.duration {
            eventDuration = dur
        } else {
            eventDuration = 86400 // all-day fallback
        }

        func makeEvent(_ s: Date) -> CalEvent {
            CalEvent(title: title, start: s, end: s.addingTimeInterval(eventDuration), uid: raw.uid)
        }

        func isExcluded(_ date: Date) -> Bool {
            raw.exdates.contains { abs($0.timeIntervalSince(date)) < 60 }
        }

        if let rruleString = raw.rrule {
            return RRuleExpander
                .occurrences(dtstart: dtstart, rrule: rruleString, in: range)
                .filter { !isExcluded($0) }
                .map { makeEvent($0) }
        } else {
            guard dtstart >= range.start && dtstart < range.end else { return [] }
            return [makeEvent(dtstart)]
        }
    }

    // MARK: - Parsing helpers

    // iCal folds long lines by inserting CRLF + space/tab. Strip the fold markers.
    private static func unfold(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n ", with: "")
            .replacingOccurrences(of: "\r\n\t", with: "")
            .replacingOccurrences(of: "\n ", with: "")
            .replacingOccurrences(of: "\n\t", with: "")
    }

    private static func afterColon(_ line: String) -> String {
        guard let i = line.firstIndex(of: ":") else { return "" }
        return String(line[line.index(after: i)...])
    }

    // Handles comma-separated dates in a single EXDATE line.
    private static func parseDates(_ line: String) -> [Date] {
        guard let colon = line.firstIndex(of: ":") else { return [] }
        let prefix = String(line[line.startIndex..<colon])
        return afterColon(line)
            .components(separatedBy: ",")
            .compactMap { v in
                parseDate(prefix + ":" + v.trimmingCharacters(in: .whitespacesAndNewlines))
            }
    }

    static func parseDate(_ line: String) -> Date? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let propPart = String(line[line.startIndex..<colon])
        let raw = String(line[line.index(after: colon)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // In case of comma-separated EXDATE values, take the first one.
        let value = raw.components(separatedBy: ",").first ?? raw

        // Extract TZID from property params e.g. DTSTART;TZID=America/New_York
        var timezone: TimeZone = .current
        if let tzRange = propPart.range(of: "TZID=") {
            let tzStr = String(propPart[tzRange.upperBound...])
                .components(separatedBy: ";").first ?? ""
            timezone = TimeZone(identifier: tzStr) ?? .current
        }

        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")

        if value.hasSuffix("Z") {                   // UTC: 20240517T120000Z
            fmt.timeZone = TimeZone(identifier: "UTC")
            fmt.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            return fmt.date(from: value)
        }
        if value.count == 15 {                      // floating / TZID: 20240517T120000
            fmt.timeZone = timezone
            fmt.dateFormat = "yyyyMMdd'T'HHmmss"
            return fmt.date(from: value)
        }
        if value.count == 8 {                       // date-only: 20240517
            fmt.timeZone = .current
            fmt.dateFormat = "yyyyMMdd"
            return fmt.date(from: value)
        }
        return nil
    }

    private static func parseDuration(_ value: String) -> TimeInterval? {
        var s = value.trimmingCharacters(in: .whitespacesAndNewlines)
        var sign: TimeInterval = 1
        if s.hasPrefix("-") { sign = -1; s = String(s.dropFirst()) }
        if s.hasPrefix("+") { s = String(s.dropFirst()) }
        guard s.hasPrefix("P") else { return nil }
        s = String(s.dropFirst())

        var total: TimeInterval = 0
        var inTime = false
        var num = ""
        for ch in s {
            if ch == "T" { inTime = true; continue }
            if ch.isNumber { num.append(ch); continue }
            guard let n = Double(num) else { return nil }
            num = ""
            switch ch {
            case "W": total += n * 7 * 86400
            case "D": total += n * 86400
            case "H": total += n * 3600
            case "M": total += inTime ? n * 60 : n * 30 * 86400
            case "S": total += n
            default: break
            }
        }
        return total * sign
    }
}
