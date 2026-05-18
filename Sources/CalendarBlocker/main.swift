import AppKit
import Foundation

// Flush stdout on every write so logs appear immediately
setbuf(stdout, nil)

// Kill any previous instance so watch.sh restarts cleanly and orphans can't pile up.
let lockURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("CalendarBlocker.pid")
if let existing = try? String(contentsOf: lockURL, encoding: .utf8),
   let oldPid = Int32(existing.trimmingCharacters(in: .whitespacesAndNewlines)),
   oldPid != getpid() {
    kill(oldPid, SIGTERM)
}
try? "\(getpid())".write(to: lockURL, atomically: true, encoding: .utf8)

print("CalendarBlocker: initializing…")

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate

print("CalendarBlocker: starting run loop…")
app.run()
