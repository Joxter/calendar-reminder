import AppKit
import Foundation

// Flush stdout on every write so logs appear immediately
setbuf(stdout, nil)

print("CalendarBlocker: initializing…")

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate

print("CalendarBlocker: starting run loop…")
app.run()
