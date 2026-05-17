import Foundation

struct CalEvent {
    let title: String
    let start: Date
    let end: Date

    var startsInSeconds: TimeInterval { start.timeIntervalSinceNow }
    var duration: TimeInterval { end.timeIntervalSince(start) }
}

// Minimal iCal parser — handles VEVENT blocks with DTSTART/DTEND/SUMMARY.
// Supports basic UTC timestamps (Z suffix) and DATE-only values.
enum ICalParser {
    static func parse(_ text: String) -> [CalEvent] {
        var events: [CalEvent] = []
        var inEvent = false
        var title: String?
        var start: Date?
        var end: Date?

        for raw in text.components(separatedBy: "\n") {
            // iCal lines can be folded (continuation starts with space/tab)
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }

            switch line {
            case "BEGIN:VEVENT":
                inEvent = true; title = nil; start = nil; end = nil
            case "END:VEVENT":
                if inEvent, let t = title, let s = start, let e = end {
                    events.append(CalEvent(title: t, start: s, end: e))
                }
                inEvent = false
            default:
                guard inEvent else { continue }
                if line.hasPrefix("SUMMARY:") {
                    title = String(line.dropFirst(8))
                } else if line.hasPrefix("DTSTART") {
                    start = parseDate(line)
                } else if line.hasPrefix("DTEND") {
                    end = parseDate(line)
                }
            }
        }
        return events
    }

    private static func parseDate(_ line: String) -> Date? {
        // Strip the property name (may include params like ;TZID=...)
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let value = String(line[line.index(after: colon)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")

        // UTC: 20240517T120000Z
        if value.hasSuffix("Z") {
            fmt.timeZone = TimeZone(identifier: "UTC")
            fmt.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            return fmt.date(from: value)
        }

        // Floating (no TZ suffix): treat as local
        if value.count == 15 {
            fmt.timeZone = .current
            fmt.dateFormat = "yyyyMMdd'T'HHmmss"
            return fmt.date(from: value)
        }

        // Date-only: 20240517 — treat as midnight local
        if value.count == 8 {
            fmt.timeZone = .current
            fmt.dateFormat = "yyyyMMdd"
            return fmt.date(from: value)
        }

        return nil
    }
}
