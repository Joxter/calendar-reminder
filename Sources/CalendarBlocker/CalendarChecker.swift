import Foundation

enum CalendarError: Error { case noURL }

struct FetchResult {
    let upcoming: [CalEvent]
    let today: [CalEvent]
    let next: CalEvent?
}

enum CalendarChecker {
    // Data(contentsOf:) is synchronous — always call from a background thread.
    static func fetch() throws -> FetchResult {
        let urls = Config.icalURLs
        guard !urls.isEmpty else { throw CalendarError.noURL }

        let now = Config.now
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: now)
        let todayEnd   = cal.date(byAdding: .day, value: 1, to: todayStart)!
        let range = DateInterval(start: todayStart, end: todayEnd)

        var allToday: [CalEvent] = []
        for url in urls {
            let email = Config.calendarEmail(from: url)
            do {
                let data = try Data(contentsOf: url)
                guard let text = String(data: data, encoding: .utf8) else { continue }
                allToday += ICalParser.parse(text, expandingIn: range, calendarEmail: email)
            } catch {
                print("Failed to fetch \(url.host ?? url.absoluteString): \(error.localizedDescription)")
            }
        }
        allToday.sort { $0.start < $1.start }

        let upcoming = allToday.filter { event in
            let secs = event.startsInSeconds
            return secs > -60 && secs <= Config.warningThreshold
        }

        let next = allToday.first { $0.start > now }

        return FetchResult(upcoming: upcoming, today: allToday, next: next)
    }
}
