import Foundation

enum Config {
    private static let d = UserDefaults.standard

    static var icalURL: URL? {
        guard let raw = d.string(forKey: "icalURL") else { return nil }
        return URL(string: raw)
    }
    static func saveIcalURL(_ raw: String) { d.set(raw, forKey: "icalURL") }

    /// Email extracted from the iCal URL path: .../ical/EMAIL_ENCODED/private-.../basic.ics
    static var calendarEmail: String? {
        guard let url = icalURL else { return nil }
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
