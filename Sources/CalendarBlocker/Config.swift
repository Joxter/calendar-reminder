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

    /// How often the calendar feeds are refetched. Alert timing is independent
    /// of this — see AppDelegate.rescheduleAlerts.
    static let fetchInterval: TimeInterval = 60

    /// Reminder offsets (minutes before event start) offered in the "Remind me" menu.
    static let reminderOptions: [Int] = [1, 2, 3, 5, 10, 15, 20, 30]

    /// Enabled reminder offsets — multiple choice, may be empty.
    static var reminderMinutes: Set<Int> {
        if let arr = d.array(forKey: "reminderMinutes") as? [Int] { return Set(arr) }
        let old = d.double(forKey: "warningThreshold")   // migrate from the single-choice key
        return [old > 0 ? Int(old / 60) : 10]
    }
    static func saveReminderMinutes(_ minutes: Set<Int>) {
        d.set(minutes.sorted(), forKey: "reminderMinutes")
    }

    static var soundEnabled: Bool {
        d.object(forKey: "soundEnabled") == nil ? true : d.bool(forKey: "soundEnabled")
    }
    static func saveSoundEnabled(_ on: Bool) { d.set(on, forKey: "soundEnabled") }

    // MARK: - Mock / Testing

    struct MockEventDef {
        let id: String
        let title: String
        let startMinute: Int     // absolute minute of the day (0..1439)
        let durationMinutes: Int
    }

    // Absolute time-of-day mock events (mirrors web/src/model.ts mockEventDefs).
    static let mockEventDefs: [MockEventDef] = [
        .init(id: "Crazy early",                       title: "Crazy early",                       startMinute:  2*60+30, durationMinutes:  42),
        .init(id: "Standup",                           title: "Standup",                           startMinute:  9*60+30, durationMinutes:  15),
        .init(id: "Ampiwise: Standup",                 title: "Ampiwise: Standup",                 startMinute: 10*60+15, durationMinutes:  15),
        .init(id: "Full-stack guild: Sptint planning", title: "Full-stack guild: Sptint planning", startMinute: 10*60+30, durationMinutes:  45),
        .init(id: "1-1 Alex, Nikolai",                 title: "1-1 Alex, Nikolai",                 startMinute: 10*60+30, durationMinutes:  30),
        .init(id: "Lunch",                             title: "Lunch",                             startMinute: 12*60+9,  durationMinutes:  60),
        .init(id: "ex1", title: "ex1", startMinute: 13*60, durationMinutes: 15),
        .init(id: "ex2", title: "ex2", startMinute: 13*60, durationMinutes: 15),
        .init(id: "ex3", title: "ex3", startMinute: 13*60, durationMinutes: 15),
        .init(id: "ex4", title: "ex4", startMinute: 13*60, durationMinutes: 15),
        .init(id: "ex5", title: "ex5", startMinute: 13*60, durationMinutes: 15),
        .init(id: "ex6", title: "ex6", startMinute: 13*60, durationMinutes: 15),
        .init(id: "very long event with very long name, probably some broken import from another systems",
              title: "very long event with very long name, probably some broken import from another systems",
              startMinute: 14*60, durationMinutes: 60),
        .init(id: "Monthly update, 152min",            title: "Monthly update, 152min",            startMinute: 16*60+15, durationMinutes: 152),
        .init(id: "Very late WTF!? and 52 min!",       title: "Very late WTF!?",                   startMinute: 23*60+23, durationMinutes:  52),
        // Screenshot preset — nice realistic day, enabled together via "Load screenshot preset"
        .init(id: "sc-standup",  title: "Team Standup",          startMinute:  9*60+30, durationMinutes:  15),
        .init(id: "sc-review",   title: "Product Review",         startMinute: 11*60,    durationMinutes:  60),
        .init(id: "sc-lunch",    title: "Lunch",                  startMinute: 12*60+30, durationMinutes:  60),
        .init(id: "sc-1on1",     title: "1:1 with Anna",          startMinute: 14*60,    durationMinutes:  30),
        .init(id: "sc-design",   title: "Design Sprint",          startMinute: 15*60+30, durationMinutes:  90),
        .init(id: "sc-retro",    title: "Weekly Retro",           startMinute: 17*60,    durationMinutes:  45),
    ]

    static let screenshotPresetIDs: Set<String> = ["sc-standup", "sc-review", "sc-lunch", "sc-1on1", "sc-design", "sc-retro"]
    // Simulated time for the screenshot preset: 10:45 → Product Review starts in 15 min
    static let screenshotPresetMinute = 10*60+45

    static var enabledMockEventIDs: Set<String> {
        Set(d.stringArray(forKey: "mockEventIDs") ?? [])
    }
    static func saveMockEventIDs(_ ids: Set<String>) { d.set(Array(ids), forKey: "mockEventIDs") }

    static var mockHideReal: Bool { d.bool(forKey: "mockHideReal") }
    static func saveMockHideReal(_ on: Bool) { d.set(on, forKey: "mockHideReal") }

    /// Absolute simulated time-of-day in minutes (0..1439); -1 means "use real time-of-day".
    static var mockMinuteOfDay: Int {
        d.object(forKey: "mockMinuteOfDay") == nil ? -1 : d.integer(forKey: "mockMinuteOfDay")
    }
    static func saveMockMinuteOfDay(_ minute: Int) { d.set(minute, forKey: "mockMinuteOfDay") }

    static var mockDayOffset: Int { d.integer(forKey: "mockDayOffset") }
    static func saveMockDayOffset(_ days: Int) { d.set(days, forKey: "mockDayOffset") }

    /// Debug: force the timeline's plain-list fallback view regardless of event count/span.
    static var forceFallback: Bool { d.bool(forKey: "forceFallback") }
    static func saveForceFallback(_ on: Bool) { d.set(on, forKey: "forceFallback") }

    static var testModeActive: Bool {
        d.bool(forKey: "testModeActive")
    }
    static func saveTestModeActive(_ on: Bool) { d.set(on, forKey: "testModeActive") }

    static var isMockActive: Bool {
        testModeActive && (mockMinuteOfDay >= 0 || mockDayOffset != 0 || !enabledMockEventIDs.isEmpty || forceFallback)
    }

    static var now: Date {
        guard testModeActive else { return Date() }
        let cal = Calendar.current
        let baseDay = cal.date(byAdding: .day, value: mockDayOffset, to: Date()) ?? Date()
        if mockMinuteOfDay >= 0 {   // absolute time-of-day override (scrubber)
            return cal.startOfDay(for: baseDay).addingTimeInterval(TimeInterval(mockMinuteOfDay) * 60)
        }
        return baseDay   // real time-of-day on the (possibly offset) day
    }
}
