import Foundation

enum Config {
    /// iCal feed URL — read from ICAL_URL env var or a .env file
    static let icalURL: URL = {
        if let raw = ProcessInfo.processInfo.environment["ICAL_URL"],
           let url = URL(string: raw) { return url }

        // Try .env in CWD, then one directory up (repo root when run from swift-app/)
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for base in [cwd, cwd.deletingLastPathComponent()] {
            let path = base.appendingPathComponent(".env")
            guard let text = try? String(contentsOf: path, encoding: .utf8) else { continue }
            for line in text.components(separatedBy: .newlines) {
                let parts = line.split(separator: "=", maxSplits: 1)
                guard parts.count == 2,
                      parts[0].trimmingCharacters(in: .whitespaces) == "ICAL_URL"
                else { continue }
                let raw = parts[1].trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                if let url = URL(string: raw) { return url }
            }
        }

        fatalError("ICAL_URL not set. Export it or add to .env in the repo root.")
    }()

    static let pollInterval: TimeInterval = 30
    static let warningThreshold: TimeInterval = 10 * 60
}
