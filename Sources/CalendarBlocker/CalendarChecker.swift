import Foundation

enum CalendarError: Error { case noURL }

struct FetchResult {
    let today: [CalEvent]
    let next: CalEvent?
}

enum CalendarChecker {
    // Data(contentsOf:) is synchronous — always call from a background thread.
    static func fetch() throws -> FetchResult {
        let urls = Config.icalURLs
        let enabledMocks = Config.testModeActive ? Config.enabledMockEventIDs : []
        let hideReal     = Config.testModeActive && Config.mockHideReal
        guard !urls.isEmpty || !enabledMocks.isEmpty else { throw CalendarError.noURL }

        let now = Config.now
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: now)
        let todayEnd   = cal.date(byAdding: .day, value: 1, to: todayStart)!
        let range = DateInterval(start: todayStart, end: todayEnd)

        var allToday: [CalEvent] = []

        if !hideReal {
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

            // Deduplicate: same event can appear in multiple calendar feeds (same UID = same event).
            var seen = Set<String>()
            allToday = allToday.filter { ev in
                let key = ev.uid ?? "\(ev.title)|\(Int(ev.start.timeIntervalSinceReferenceDate))"
                return seen.insert(key).inserted
            }
        }

        // Inject enabled mock events at their absolute time-of-day on the simulated day.
        for def in Config.mockEventDefs where enabledMocks.contains(def.id) {
            let start = todayStart.addingTimeInterval(TimeInterval(def.startMinute) * 60)
            let end   = start.addingTimeInterval(TimeInterval(def.durationMinutes) * 60)
            allToday.append(CalEvent(title: def.title, start: start, end: end,
                                     uid: "mock_\(def.id)", calendarName: "Mock", calendarEmail: nil))
        }

        allToday.sort { $0.start < $1.start }

        let recentCutoff = now.addingTimeInterval(-5 * 60)
        let next = allToday.first { $0.end > now && $0.start >= recentCutoff }

        return FetchResult(today: allToday, next: next)
    }
}
