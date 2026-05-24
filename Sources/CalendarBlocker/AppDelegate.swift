import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var shown = Set<String>()           // pollQueue only
    private var windows: [ReminderWindow] = []  // main thread only
    private var pollTimer: DispatchSourceTimer?
    private var statusBar: StatusBarController?
    private var lastResult: FetchResult?        // main thread only

    private let pollQueue = DispatchQueue(label: "com.calendarblocker.poll", qos: .utility)
    private var isFirstPoll = true              // pollQueue only

    func applicationDidFinishLaunching(_ notification: Notification) {
        installEditMenu()
        let bar = StatusBarController()
        bar.onURLChanged = { [weak self] in self?.scheduleImmediatePoll() }
        bar.onOpenWindow = { [weak self] in
            guard let self else { return }
            let result = self.lastResult
            DispatchQueue.main.async { self.showReminder(event: result?.next, today: result?.today ?? []) }
            self.scheduleImmediatePoll()
        }
        bar.onMockChanged = { [weak self] in self?.scheduleImmediatePoll() }
        bar.onClearShown = { [weak self] in
            self?.pollQueue.async {
                self?.shown.removeAll()
                self?.pollOnce()
            }
        }
        statusBar = bar

        print("Calendar Blocker started. Polling every \(Int(Config.pollInterval))s, warning \(Int(Config.warningThreshold / 60))min before events.")
        startPollTimer()
    }

    func applicationWillTerminate(_ notification: Notification) {
        pollTimer?.cancel()
        let lockURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("CalendarBlocker.pid")
        try? FileManager.default.removeItem(at: lockURL)
    }

    // MARK: - Poll timer (any thread — safe because pollTimer mutations are bracketed by cancel+create)

    private func startPollTimer(isStartup: Bool = true) {
        isFirstPoll = isStartup
        let timer = DispatchSource.makeTimerSource(queue: pollQueue)
        timer.schedule(deadline: .now(), repeating: Config.pollInterval, leeway: .seconds(1))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let first = self.isFirstPoll
            self.isFirstPoll = false
            self.pollOnce(isStartup: first)
        }
        timer.resume()
        pollTimer = timer
    }

    private func restartPollTimer() {
        pollTimer?.cancel()
        startPollTimer(isStartup: false)
    }

    private func scheduleImmediatePoll() {
        pollQueue.async { [weak self] in self?.pollOnce() }
    }

    // MARK: - Poll (runs exclusively on pollQueue — no concurrent access to `shown`)

    private func pollOnce(isStartup: Bool = false) {
        print("Checking calendar…")
        do {
            let result = try CalendarChecker.fetch()

            // Keep only keys that still correspond to today's events, so the set
            // doesn't grow forever and old UIDs can't suppress re-triggered events.
            let validKeys = Set(result.today.map { $0.uid ?? "\($0.title)|\($0.start)" })
            shown = shown.intersection(validKeys)

            var eventsToShow: [CalEvent] = []
            if !isStartup {
                for event in result.upcoming {
                    let key = event.uid ?? "\(event.title)|\(event.start)"
                    if shown.insert(key).inserted {
                        eventsToShow.append(event)
                    }
                }
            }

            if let next = result.next {
                let secs = next.startsInSeconds
                let h = Int(secs) / 3600, m = Int(secs) % 3600 / 60, s = Int(secs) % 60
                let eta = h > 0 ? "in \(h)h \(m)m" : (m > 0 ? "in \(m)m \(s)s" : "in \(s)s")
                print("Next event: \"\(next.title)\" at \(timeStr(next.start)) (\(eta))")
            } else {
                print("No upcoming events found.")
            }
            print("Next check in \(Int(Config.pollInterval))s.")

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.lastResult = result
                self.statusBar?.update(next: result.next)
                if isStartup {
                    self.showReminder(event: result.next, today: result.today)
                } else {
                    for ev in eventsToShow {
                        print("Reminding: \(ev.title) at \(self.timeStr(ev.start))")
                        self.showReminder(event: ev, today: result.today)
                    }
                }
            }

        } catch CalendarError.noURL {
            print("No calendar URL configured. Use the menu bar to set one.")
            DispatchQueue.main.async { [weak self] in self?.statusBar?.update(next: nil) }
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
