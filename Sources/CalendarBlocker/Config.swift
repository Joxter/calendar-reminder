import Foundation

enum Config {
    private static let d = UserDefaults.standard

    /// Raw textarea content as entered by the user (URLs separated by whitespace/newlines).
    static var icalURLsText: String {
        if let text = d.string(forKey: "icalURLs") { return text }
        return d.string(forKey: "icalURL") ?? ""   // migrate from old single-URL key
    }

    static var icalURLs: [URL] {
        icalURLsText
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .compactMap { URL(string: $0) }
    }

    static func saveIcalURLs(_ text: String) { d.set(text, forKey: "icalURLs") }

    /// Email extracted from a Google Calendar iCal URL path: .../ical/EMAIL_ENCODED/private-.../basic.ics
    static func calendarEmail(from url: URL) -> String? {
        let parts = url.pathComponents
        guard let idx = parts.firstIndex(of: "ical"), idx + 1 < parts.count else { return nil }
        return parts[idx + 1].removingPercentEncoding
    }

    static let pollInterval: TimeInterval = 60

    static var warningThreshold: TimeInterval {
        let v = d.double(forKey: "warningThreshold")
        return v > 0 ? v : 10 * 60
    }
    static func saveWarningThreshold(_ seconds: TimeInterval) { d.set(seconds, forKey: "warningThreshold") }

    static var soundEnabled: Bool {
        d.object(forKey: "soundEnabled") == nil ? true : d.bool(forKey: "soundEnabled")
    }
    static func saveSoundEnabled(_ on: Bool) { d.set(on, forKey: "soundEnabled") }

    // MARK: - Mock / Testing

    struct MockEventDef {
        let id: String
        let title: String
        let offsetMinutes: Int   // minutes from Config.now; negative = already started
        let durationMinutes: Int
    }

    static let mockEventDefs: [MockEventDef] = [
        .init(id: "very_long",  title: "very long event with <b>very long name</b>, probably some broken import from another systems",      offsetMinutes:  90, durationMinutes: 180),
        .init(id: "inprogress", title: "All-hands",          offsetMinutes: -20, durationMinutes: 60),
        .init(id: "verysoon",   title: "Standup",            offsetMinutes:   1, durationMinutes: 15),
        .init(id: "soon",       title: "Design Review",      offsetMinutes:   8, durationMinutes: 60),
        .init(id: "upcoming",   title: "Lunch",              offsetMinutes:  30, durationMinutes: 60),
        .init(id: "overlap1",   title: "Sprint Planning",    offsetMinutes:  65, durationMinutes: 60),
        .init(id: "overlap2",   title: "Retrospective",      offsetMinutes:  90, durationMinutes: 60),
        .init(id: "later",      title: "1:1 with Manager",   offsetMinutes: 160, durationMinutes: 30),
    ]

    static var enabledMockEventIDs: Set<String> {
        Set(d.stringArray(forKey: "mockEventIDs") ?? [])
    }
    static func saveMockEventIDs(_ ids: Set<String>) { d.set(Array(ids), forKey: "mockEventIDs") }

    static var mockHideReal: Bool { d.bool(forKey: "mockHideReal") }
    static func saveMockHideReal(_ on: Bool) { d.set(on, forKey: "mockHideReal") }

    static var mockTimeOffset: TimeInterval { d.double(forKey: "mockTimeOffset") }
    static func saveMockTimeOffset(_ secs: TimeInterval) { d.set(secs, forKey: "mockTimeOffset") }

    static var mockDayOffset: Int { d.integer(forKey: "mockDayOffset") }
    static func saveMockDayOffset(_ days: Int) { d.set(days, forKey: "mockDayOffset") }

    static var testModeActive: Bool {
        d.bool(forKey: "testModeActive")
    }
    static func saveTestModeActive(_ on: Bool) { d.set(on, forKey: "testModeActive") }

    static var isMockActive: Bool {
        testModeActive && (mockTimeOffset != 0 || mockDayOffset != 0 || !enabledMockEventIDs.isEmpty)
    }

    static var now: Date {
        guard testModeActive else { return Date() }
        let base = Calendar.current.date(byAdding: .day, value: mockDayOffset, to: Date()) ?? Date()
        return base.addingTimeInterval(mockTimeOffset)
    }
}
