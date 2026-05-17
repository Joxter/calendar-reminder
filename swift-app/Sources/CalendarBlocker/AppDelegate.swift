import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var shown = Set<String>()
    private var windows: [ReminderWindow] = []
    private var pollThread: Thread?

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("Calendar Blocker started. Polling every \(Int(Config.pollInterval))s, warning \(Int(Config.warningThreshold / 60))min before events.")
        let t = Thread { self.pollLoop(isStartup: true) }
        t.name = "CalendarPoller"
        t.start()
        pollThread = t
    }

    func applicationWillTerminate(_ notification: Notification) {
        pollThread?.cancel()
    }

    // MARK: - Poll loop (runs on background thread)

    private func pollLoop(isStartup: Bool) {
        var startup = isStartup
        while !Thread.current.isCancelled {
            print("Checking calendar…")
            do {
                let result = try CalendarChecker.fetch()

                if startup {
                    if let next = result.next {
                        DispatchQueue.main.async { self.showReminder(event: next, today: result.today) }
                    }
                    startup = false
                } else {
                    for event in result.upcoming {
                        let key = "\(event.title)|\(event.start)"
                        guard !shown.contains(key) else { continue }
                        shown.insert(key)
                        print("Reminding: \(event.title) at \(timeStr(event.start))")
                        let ev = event, td = result.today
                        DispatchQueue.main.async { self.showReminder(event: ev, today: td) }
                    }
                    if shown.count > 200 { shown.removeAll() }
                }

                if let next = result.next {
                    let secs = next.startsInSeconds
                    let h = Int(secs) / 3600, m = Int(secs) % 3600 / 60, s = Int(secs) % 60
                    let eta = h > 0 ? "in \(h)h \(m)m" : (m > 0 ? "in \(m)m \(s)s" : "in \(s)s")
                    print("Next event: \"\(next.title)\" at \(timeStr(next.start)) (\(eta))")
                } else {
                    print("No upcoming events found.")
                }

            } catch {
                print("Fetch error: \(error.localizedDescription)")
            }

            print("Next check in \(Int(Config.pollInterval))s.")
            Thread.sleep(forTimeInterval: Config.pollInterval)
        }
    }

    // MARK: - Main thread

    @MainActor
    private func showReminder(event: CalEvent, today: [CalEvent]) {
        let win = ReminderWindow(event: event, todayEvents: today)
        windows.removeAll { !$0.isVisible }
        windows.append(win)
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func timeStr(_ date: Date) -> String {
        let fmt = DateFormatter(); fmt.dateFormat = "HH:mm"
        return fmt.string(from: date)
    }
}
