import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var shown = Set<String>()
    private var windows: [ReminderWindow] = []
    private var pollThread: Thread?
    private var statusBar: StatusBarController?
    private var lastResult: FetchResult?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installEditMenu()
        let bar = StatusBarController()
        bar.onURLChanged = { [weak self] in
            guard let self else { return }
            let t = Thread { self.pollOnce() }
            t.name = "ImmediatePoll"
            t.start()
        }
        bar.onOpenWindow = { [weak self] in
            guard let self else { return }
            let result = self.lastResult
            DispatchQueue.main.async { self.showReminder(event: result?.next, today: result?.today ?? []) }
        }
        statusBar = bar

        print("Calendar Blocker started. Polling every \(Int(Config.pollInterval))s, warning \(Int(Config.warningThreshold / 60))min before events.")
        let t = Thread { self.pollLoop(isStartup: true) }
        t.name = "CalendarPoller"
        t.start()
        pollThread = t
    }

    func applicationWillTerminate(_ notification: Notification) {
        pollThread?.cancel()
        let lockURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("CalendarBlocker.pid")
        try? FileManager.default.removeItem(at: lockURL)
    }

    // MARK: - Poll loop (runs on background thread)

    private func pollLoop(isStartup: Bool) {
        var startup = isStartup
        while !Thread.current.isCancelled {
            pollOnce(isStartup: startup)
            startup = false
            print("Next check in \(Int(Config.pollInterval))s.")
            Thread.sleep(forTimeInterval: Config.pollInterval)
        }
    }

    // Single poll — safe to call from any background thread (including the immediate re-poll).
    private func pollOnce(isStartup: Bool = false) {
        print("Checking calendar…")
        do {
            let result = try CalendarChecker.fetch()
            lastResult = result

            if isStartup {
                let ev = result.next, td = result.today
                DispatchQueue.main.async { self.showReminder(event: ev, today: td) }
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

            statusBar?.update(next: result.next)

            if let next = result.next {
                let secs = next.startsInSeconds
                let h = Int(secs) / 3600, m = Int(secs) % 3600 / 60, s = Int(secs) % 60
                let eta = h > 0 ? "in \(h)h \(m)m" : (m > 0 ? "in \(m)m \(s)s" : "in \(s)s")
                print("Next event: \"\(next.title)\" at \(timeStr(next.start)) (\(eta))")
            } else {
                print("No upcoming events found.")
            }

        } catch CalendarError.noURL {
            print("No calendar URL configured. Use the menu bar to set one.")
            statusBar?.update(next: nil)
        } catch {
            print("Fetch error: \(error.localizedDescription)")
        }
    }

    // MARK: - Main thread

    @MainActor
    private func showReminder(event: CalEvent?, today: [CalEvent]) {
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

    // Accessory-policy apps have no main menu, so ⌘C/⌘V are never routed to text fields.
    // Installing a minimal Edit menu restores standard keyboard shortcuts.
    private func installEditMenu() {
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Cut",        action: #selector(NSText.cut(_:)),       keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy",       action: #selector(NSText.copy(_:)),      keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste",      action: #selector(NSText.paste(_:)),     keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editItem.submenu = editMenu
        let mainMenu = NSMenu()
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
    }
}
