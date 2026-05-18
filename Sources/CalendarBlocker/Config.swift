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

    static var pollInterval: TimeInterval {
        let v = d.double(forKey: "pollInterval")
        return v > 0 ? v : 30
    }
    static func savePollInterval(_ seconds: TimeInterval) { d.set(seconds, forKey: "pollInterval") }

    static var warningThreshold: TimeInterval {
        let v = d.double(forKey: "warningThreshold")
        return v > 0 ? v : 10 * 60
    }
    static func saveWarningThreshold(_ seconds: TimeInterval) { d.set(seconds, forKey: "warningThreshold") }

    static var soundEnabled: Bool {
        d.object(forKey: "soundEnabled") == nil ? true : d.bool(forKey: "soundEnabled")
    }
    static func saveSoundEnabled(_ on: Bool) { d.set(on, forKey: "soundEnabled") }

    // Set to true to freeze "now" at 13:00 today for UI testing
    static let mockNowEnabled = false
    static var now: Date {
        guard mockNowEnabled else { return Date() }
        return Calendar.current.date(bySettingHour: 13, minute: 8, second: 0, of: Date())!
    }
}
