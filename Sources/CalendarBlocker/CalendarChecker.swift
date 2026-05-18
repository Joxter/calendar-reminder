import Foundation

enum CalendarError: Error { case noURL }

struct FetchResult {
    let upcoming: [CalEvent]
    let today: [CalEvent]
    let next: CalEvent?
}

enum CalendarChecker {
    static func fetch() throws -> FetchResult {
        guard let url = Config.icalURL else { throw CalendarError.noURL }
        // Data(contentsOf:) is synchronous — always call from a background thread.
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }

        let now = Config.now
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: now)
        let todayEnd   = cal.date(byAdding: .day, value: 1, to: todayStart)!

        let today = ICalParser.parse(text, expandingIn: DateInterval(start: todayStart, end: todayEnd))

        let upcoming = today.filter { event in
            let secs = event.startsInSeconds
            return secs > -60 && secs <= Config.warningThreshold
        }

        let next = today.first { $0.start > now }

        return FetchResult(upcoming: upcoming, today: today, next: next)
    }
}
