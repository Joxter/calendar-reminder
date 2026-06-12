import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var firedAlerts = Set<String>()      // main thread — "eventKey|minutes" alerts already shown
    private var reminderWindow: ReminderWindow?  // main thread — the single shared window
    private var alertTimer: Timer?               // main thread — aimed at the next exact alert time
    private var pollTimer: DispatchSourceTimer?
    private var statusBar: StatusBarController?
    private var lastResult: FetchResult?         // main thread only
    private var refreshCalendarPending = false   // main thread only — recreate open calendar window after next poll
    private var isFirstResult = true             // main thread only — show window once, silence past-due alerts

    private let pollQueue = DispatchQueue(label: "com.calendarblocker.poll", qos: .utility)

    func applicationDidFinishLaunching(_ notification: Notification) {
        installEditMenu()
        let bar = StatusBarController()
        bar.onURLChanged = { [weak self] in self?.scheduleImmediatePoll() }
        bar.onOpenWindow = { [weak self] in
            guard let self else { return }
            let result = self.lastResult
            DispatchQueue.main.async { self.showReminder(event: nil, today: result?.today ?? []) }
            self.scheduleImmediatePoll()
        }
        bar.onMockChanged = { [weak self] in
            self?.refreshCalendarPending = true   // recreate any open calendar window with fresh events
            self?.scheduleImmediatePoll()
        }
        bar.onTimeChanged = { [weak self] in
            DispatchQueue.main.async {
                self?.refreshOpenWindowForTime()
                self?.rescheduleAlerts(silencePastDue: true)   // re-aim timers at the simulated clock
            }
        }
        bar.onRemindersChanged = { [weak self] in
            DispatchQueue.main.async { self?.rescheduleAlerts() }
        }
        bar.onClearShown = { [weak self] in
            DispatchQueue.main.async { self?.firedAlerts.removeAll() }
            self?.scheduleImmediatePoll()
        }
        statusBar = bar

        print("Calendar Blocker started. Fetching every \(Int(Config.fetchInterval))s, reminders \(Config.reminderMinutes.sorted())min before events.")
        startPollTimer()
    }

    func applicationWillTerminate(_ notification: Notification) {
        pollTimer?.cancel()
        let lockURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("CalendarBlocker.pid")
        try? FileManager.default.removeItem(at: lockURL)
    }

    // MARK: - Poll timer (any thread — safe because pollTimer mutations are bracketed by cancel+create)

    private func startPollTimer() {
        let timer = DispatchSource.makeTimerSource(queue: pollQueue)
        timer.schedule(deadline: .now(), repeating: Config.fetchInterval, leeway: .seconds(1))
        timer.setEventHandler { [weak self] in self?.pollOnce() }
        timer.resume()
        pollTimer = timer
    }

    private func scheduleImmediatePoll() {
        pollQueue.async { [weak self] in self?.pollOnce() }
    }

    // MARK: - Poll (runs exclusively on pollQueue) — fetches only; alerts are scheduled separately

    private func pollOnce() {
        print("Checking calendar…")
        do {
            let result = try CalendarChecker.fetch()

            if let next = result.next {
                let secs = next.startsInSeconds
                let h = Int(secs) / 3600, m = Int(secs) % 3600 / 60, s = Int(secs) % 60
                let eta = h > 0 ? "in \(h)h \(m)m" : (m > 0 ? "in \(m)m \(s)s" : "in \(s)s")
                print("Next event: \"\(next.title)\" at \(timeStr(next.start)) (\(eta))")
            } else {
                print("No upcoming events found.")
            }
            print("Next check in \(Int(Config.fetchInterval))s.")

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.lastResult = result
                self.statusBar?.update(next: result.next)
                let first = self.isFirstResult
                self.isFirstResult = false
                if first {
                    self.showReminder(event: result.next, today: result.today)
                }
                self.rescheduleAlerts(silencePastDue: first)
                if self.refreshCalendarPending {
                    self.refreshCalendarPending = false
                    self.refreshOpenCalendarWindow(today: result.today)
                }
            }

        } catch CalendarError.noURL {
            print("No calendar URL configured. Use the menu bar to set one.")
            DispatchQueue.main.async { [weak self] in self?.statusBar?.update(next: nil) }
        } catch {
            print("Fetch error: \(error.localizedDescription)")
        }
    }

    // MARK: - Alert scheduling (main thread)
    //
    // Alerts fire from their own timer aimed at the exact moment (event start
    // minus each enabled offset), independent of the fetch cadence — so a
    // "1 min before" reminder opens showing ~1:00 on the countdown.

    /// Alerts due within this window fire now; the timer aims half of it early so
    /// the countdown still reads a round value (1:00, not 0:59) when it opens.
    private let alertTolerance: TimeInterval = 0.5

    private func alertKey(_ event: CalEvent, _ minutes: Int) -> String {
        "\(event.uid ?? "\(event.title)|\(event.start)")|\(minutes)"
    }

    @MainActor
    private func rescheduleAlerts(silencePastDue: Bool = false) {
        alertTimer?.invalidate()
        alertTimer = nil
        guard let result = lastResult else { return }
        let now = Config.now

        // Keep only keys for events that still exist, so the set doesn't grow
        // forever and old UIDs can't suppress re-triggered events.
        let validKeys = Set(result.today.flatMap { ev in Config.reminderOptions.map { alertKey(ev, $0) } })
        firedAlerts.formIntersection(validKeys)

        var dueEvents: [CalEvent] = []
        var nextAlertAt: Date?

        for event in result.today where event.start > now {
            for minutes in Config.reminderMinutes {
                let key = alertKey(event, minutes)
                guard !firedAlerts.contains(key) else { continue }
                let alertAt = event.start.addingTimeInterval(TimeInterval(-minutes * 60))
                if alertAt.timeIntervalSince(now) <= alertTolerance {
                    firedAlerts.insert(key)
                    if !silencePastDue { dueEvents.append(event) }
                } else if nextAlertAt == nil || alertAt < nextAlertAt! {
                    nextAlertAt = alertAt
                }
            }
        }

        if let soonest = dueEvents.min(by: { $0.start < $1.start }) {
            print("Reminding: \(soonest.title) at \(timeStr(soonest.start))")
            showReminder(event: soonest, today: result.today)
        }

        if let nextAlertAt {
            let delay = max(0.1, nextAlertAt.timeIntervalSince(now) - alertTolerance / 2)
            let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
                DispatchQueue.main.async { self?.rescheduleAlerts() }
            }
            RunLoop.main.add(timer, forMode: .common)   // .common: fires even while a menu is open
            alertTimer = timer
        }
    }

    // MARK: - Main thread

    // Live time-scrubber: refresh the open window in place instead of recreating it.
    @MainActor
    private func refreshOpenWindowForTime() {
        if let win = reminderWindow, win.isVisible { win.refreshForTimeChange() }
    }

    // Mock change (events / day / hide-real / force-fallback): rebuild the open
    // calendar window with fresh events so the change is visible immediately.
    @MainActor
    private func refreshOpenCalendarWindow(today: [CalEvent]) {
        guard let win = reminderWindow, win.isVisible, win.isCalendarWindow else { return }
        showReminder(event: nil, today: today)
    }

    // Single shared window: reuse (rebuild + move to front) instead of stacking new ones.
    @MainActor
    private func showReminder(event: CalEvent?, today: [CalEvent]) {
        let win = reminderWindow ?? ReminderWindow()
        reminderWindow = win
        win.configure(event: event, todayEvents: today)
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
