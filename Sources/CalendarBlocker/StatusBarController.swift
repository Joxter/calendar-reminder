import AppKit

final class StatusBarController: NSObject {
    private let item: NSStatusItem
    private var nextEvent: CalEvent?
    private var refreshTimer: Timer?

    /// Called after the user saves a new calendar URL.
    var onURLChanged: (() -> Void)?
    /// Called when the user clicks "Open Calendar" in the menu.
    var onOpenWindow: (() -> Void)?
    /// Called when any mock/testing setting changes — triggers an immediate re-poll.
    var onMockChanged: (() -> Void)?
    /// Called when only the simulated clock moved — refresh open windows in place (no re-poll).
    var onTimeChanged: (() -> Void)?
    /// Called when the user asks to clear the shown-reminders set and re-poll.
    var onClearShown: (() -> Void)?

    // Time-scrubber controls (live HH:mm label + slider).
    private weak var scrubberLabel: NSTextField?
    private weak var scrubberSlider: NSSlider?

    override init() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        buildMenu()
        scheduleRefreshTimer()
        applyDisplay()
    }

    // Called from AppDelegate after every poll (safe to call from any thread).
    func update(next: CalEvent?) {
        DispatchQueue.main.async { [weak self] in
            self?.nextEvent = next
            self?.applyDisplay()
            self?.updateMenuEventItem()
        }
    }

    // MARK: - Button display

    private func applyDisplay() {
        guard let button = item.button else { return }

        let secs = nextEvent.map { $0.startsInSeconds } ?? .infinity

        let symbolName: String
        let tint: NSColor?
        var label: String

        if secs <= 0 {
            symbolName = "calendar.badge.clock"; tint = .systemRed;    label = "now"
        } else if secs < 5 * 60 {
            let m = max(1, Int(secs / 60 + 0.5))
            symbolName = "calendar.badge.clock"; tint = .systemOrange; label = "\(m)m"
        } else if secs < .infinity {
            let m = Int(secs / 60 + 0.5)
            if m >= 60 {
                let h = m / 60, rm = m % 60
                label = rm > 0 ? "\(h)h \(rm)m" : "\(h)h"
            } else {
                label = "\(m)m"
            }
            symbolName = "calendar"; tint = nil
        } else {
            symbolName = "calendar"; tint = nil; label = ""
        }

        // Append a dot when any mock/testing feature is active so it's obvious.
        if Config.isMockActive {
            label = label.isEmpty ? "·" : "\(label) ·"
        }

        let cfg = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        if let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Calendar")?
            .withSymbolConfiguration(cfg) {
            img.isTemplate = (tint == nil)
            button.image = img
        }
        button.contentTintColor = tint
        button.title = label.isEmpty ? "" : "  \(label)"
        button.imagePosition = label.isEmpty ? .imageOnly : .imageLeft
    }

    // MARK: - Menu

    private func buildMenu() {
        let menu = NSMenu()

        let eventItem = NSMenuItem(title: "No upcoming events", action: nil, keyEquivalent: "")
        eventItem.isEnabled = false
        eventItem.tag = 42
        menu.addItem(eventItem)

        menu.addItem(.separator())

        let urlItem = NSMenuItem(title: "Set Calendar URLs…", action: #selector(setCalendarURL), keyEquivalent: ",")
        urlItem.target = self
        menu.addItem(urlItem)

        menu.addItem(.separator())

        menu.addItem(makeWarningThresholdMenu())

        let soundItem = NSMenuItem(title: "Sound", action: #selector(toggleSound), keyEquivalent: "")
        soundItem.target = self
        soundItem.state = Config.soundEnabled ? .on : .off
        soundItem.tag = 99
        menu.addItem(soundItem)

        menu.addItem(.separator())

        let calItem = NSMenuItem(title: "Open Calendar", action: #selector(openCalendarWindow), keyEquivalent: "o")
        calItem.target = self
        menu.addItem(calItem)

        menu.addItem(makeTestingMenu())

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        item.menu = menu
    }

    private func makeWarningThresholdMenu() -> NSMenuItem {
        let options: [(String, TimeInterval)] = [
            ("5 minutes before", 5 * 60), ("10 minutes before", 10 * 60),
            ("15 minutes before", 15 * 60), ("30 minutes before", 30 * 60)
        ]
        let sub = NSMenu()
        for (title, secs) in options {
            let it = NSMenuItem(title: title, action: #selector(setWarningThreshold(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = secs as AnyObject
            it.state = Config.warningThreshold == secs ? .on : .off
            sub.addItem(it)
        }
        let parent = NSMenuItem(title: "Remind me", action: nil, keyEquivalent: "")
        parent.submenu = sub
        parent.tag = 11
        return parent
    }

    // MARK: - Testing menu

    private func makeTestingMenu() -> NSMenuItem {
        let sub = NSMenu()

        // Master on/off switch — keeps all settings intact when disabled
        let enableItem = NSMenuItem(title: "Test mode enabled",
                                    action: #selector(toggleTestMode(_:)), keyEquivalent: "")
        enableItem.target = self
        enableItem.state = Config.testModeActive ? .on : .off
        enableItem.tag = 25
        sub.addItem(enableItem)

        sub.addItem(.separator())

        // Section: mock events
        let evHdr = NSMenuItem(title: "Inject mock events:", action: nil, keyEquivalent: "")
        evHdr.isEnabled = false
        sub.addItem(evHdr)

        let enabledIDs = Config.enabledMockEventIDs
        for def in Config.mockEventDefs {
            let it = NSMenuItem(title: mockEventMenuTitle(def),
                                action: #selector(toggleMockEvent(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = def.id
            it.state = enabledIDs.contains(def.id) ? .on : .off
            it.indentationLevel = 1
            sub.addItem(it)
        }

        sub.addItem(.separator())

        let hideReal = NSMenuItem(title: "Hide real events", action: #selector(toggleHideReal(_:)), keyEquivalent: "")
        hideReal.target = self
        hideReal.state = Config.mockHideReal ? .on : .off
        hideReal.tag = 21
        sub.addItem(hideReal)

        let forceFallback = NSMenuItem(title: "Force fallback list", action: #selector(toggleForceFallback(_:)), keyEquivalent: "")
        forceFallback.target = self
        forceFallback.state = Config.forceFallback ? .on : .off
        forceFallback.tag = 22
        sub.addItem(forceFallback)

        sub.addItem(.separator())

        // Section: day selection
        let dayHdr = NSMenuItem(title: "Choose day:", action: nil, keyEquivalent: "")
        dayHdr.isEnabled = false
        sub.addItem(dayHdr)

        let days: [(String, Int)] = [
            ("Last week",    -7),
            ("2 days ago",   -2),
            ("Yesterday",    -1),
            ("Today",         0),
            ("Tomorrow",     +1),
            ("2 days ahead", +2),
            ("Next week",    +7),
        ]
        let currentDay = Config.mockDayOffset
        for (title, offset) in days {
            let it = NSMenuItem(title: title, action: #selector(setMockDayOffset(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = offset as AnyObject
            it.state = currentDay == offset ? .on : .off
            it.indentationLevel = 1
            sub.addItem(it)
        }

        sub.addItem(.separator())

        // Section: time simulation — continuous scrubber over the whole day.
        let timeHdr = NSMenuItem(title: "Simulate time:", action: nil, keyEquivalent: "")
        timeHdr.isEnabled = false
        sub.addItem(timeHdr)
        sub.addItem(makeTimeScrubberItem())

        sub.addItem(.separator())

        let forceCheck = NSMenuItem(title: "Force check now", action: #selector(forceCheckNow), keyEquivalent: "")
        forceCheck.target = self
        sub.addItem(forceCheck)

        let clearShown = NSMenuItem(title: "Clear shown reminders", action: #selector(clearShownReminders), keyEquivalent: "")
        clearShown.target = self
        sub.addItem(clearShown)

        let parent = NSMenuItem(title: "Testing", action: nil, keyEquivalent: "")
        parent.submenu = sub
        parent.tag = 20
        return parent
    }

    private func mockEventMenuTitle(_ def: Config.MockEventDef) -> String {
        let timeStr = String(format: "%02d:%02d", def.startMinute / 60, def.startMinute % 60)
        let d = def.durationMinutes
        let durStr = d >= 60 ? (d % 60 > 0 ? "\(d/60)h \(d%60)m" : "\(d/60)h") : "\(d)m"
        return "\(def.title)  \(timeStr) · \(durStr)"
    }

    // MARK: - Time scrubber (custom menu view)

    /// Current scrubber minute-of-day: the simulated value when set, else wall-clock.
    private func currentScrubMinute() -> Int {
        if Config.mockMinuteOfDay >= 0 { return Config.mockMinuteOfDay }
        let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    private func scrubberLabelText() -> String {
        let m = currentScrubMinute()
        let s = String(format: "%02d:%02d", m / 60, m % 60)
        return Config.mockMinuteOfDay >= 0 ? "Simulated time:  \(s)" : "Simulated time:  \(s)  (real-time)"
    }

    private func makeTimeScrubberItem() -> NSMenuItem {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 52))

        let label = NSTextField(labelWithString: scrubberLabelText())
        label.frame = NSRect(x: 21, y: 30, width: 230, height: 16)
        label.font = NSFont.systemFont(ofSize: 12)
        container.addSubview(label)
        self.scrubberLabel = label

        let slider = NSSlider(value: Double(currentScrubMinute()), minValue: 0, maxValue: 1439,
                              target: self, action: #selector(timeScrubbed(_:)))
        slider.frame = NSRect(x: 21, y: 6, width: 168, height: 19)
        slider.isContinuous = true
        container.addSubview(slider)
        self.scrubberSlider = slider

        let reset = NSButton(title: "Real-time", target: self, action: #selector(resetTimeScrub))
        reset.frame = NSRect(x: 192, y: 3, width: 64, height: 24)
        reset.bezelStyle = .rounded
        reset.font = NSFont.systemFont(ofSize: 10)
        container.addSubview(reset)

        let item = NSMenuItem()
        item.view = container
        return item
    }

    // MARK: - Testing actions

    @objc private func toggleMockEvent(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        var ids = Config.enabledMockEventIDs
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        Config.saveMockEventIDs(ids)
        sender.state = ids.contains(id) ? .on : .off
        applyDisplay()
        onMockChanged?()
    }

    @objc private func toggleHideReal(_ sender: NSMenuItem) {
        let newVal = !Config.mockHideReal
        Config.saveMockHideReal(newVal)
        sender.state = newVal ? .on : .off
        onMockChanged?()
    }

    @objc private func timeScrubbed(_ sender: NSSlider) {
        Config.saveMockMinuteOfDay(Int(sender.doubleValue.rounded()))
        scrubberLabel?.stringValue = scrubberLabelText()
        applyDisplay()
        onTimeChanged?()   // live, in-place: events are unchanged, only the clock moved
    }

    @objc private func resetTimeScrub() {
        Config.saveMockMinuteOfDay(-1)
        scrubberSlider?.doubleValue = Double(currentScrubMinute())
        scrubberLabel?.stringValue = scrubberLabelText()
        applyDisplay()
        onTimeChanged?()
    }

    @objc private func toggleForceFallback(_ sender: NSMenuItem) {
        let newVal = !Config.forceFallback
        Config.saveForceFallback(newVal)
        sender.state = newVal ? .on : .off
        onMockChanged?()   // changes the right-column layout → rebuild the window
    }

    @objc private func toggleTestMode(_ sender: NSMenuItem) {
        let newVal = !Config.testModeActive
        Config.saveTestModeActive(newVal)
        sender.state = newVal ? .on : .off
        applyDisplay()
        onMockChanged?()
    }

    @objc private func setMockDayOffset(_ sender: NSMenuItem) {
        guard let days = sender.representedObject as? Int else { return }
        Config.saveMockDayOffset(days)
        if let testSub = item.menu?.item(withTag: 20)?.submenu {
            for it in testSub.items {
                guard it.action == #selector(setMockDayOffset(_:)),
                      let offset = it.representedObject as? Int else { continue }
                it.state = offset == days ? .on : .off
            }
        }
        applyDisplay()
        onMockChanged?()
    }

    @objc private func forceCheckNow() { onMockChanged?() }

    @objc private func clearShownReminders() { onClearShown?() }

    // MARK: - Standard actions

    private func refreshSubmenuStates() {
        if let warnMenu = item.menu?.item(withTag: 11)?.submenu {
            for it in warnMenu.items {
                it.state = (it.representedObject as? TimeInterval) == Config.warningThreshold ? .on : .off
            }
        }
        item.menu?.item(withTag: 99)?.state = Config.soundEnabled ? .on : .off
    }

    private static let eventTimeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()

    private func updateMenuEventItem() {
        guard let menuItem = item.menu?.item(withTag: 42) else { return }
        if let ev = nextEvent {
            menuItem.title = "\(ev.title)  ·  \(StatusBarController.eventTimeFmt.string(from: ev.start))"
        } else {
            menuItem.title = "No upcoming events today"
        }
    }

    @objc private func setCalendarURL() {
        let alert = NSAlert()
        alert.messageText = "Set Calendar URLs"
        alert.informativeText = "Paste iCal URLs, one per line (Google Calendar → Settings → Secret address in iCal format):"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 440, height: 90))
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 440, height: 90))
        textView.minSize = NSSize(width: 0, height: 90)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.containerSize = NSSize(width: 440, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.isEditable = true
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.string = Config.icalURLsText
        scrollView.documentView = textView

        alert.accessoryView = scrollView
        alert.window.initialFirstResponder = textView

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let raw = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        Config.saveIcalURLs(raw)
        onURLChanged?()
    }

    @objc private func setWarningThreshold(_ sender: NSMenuItem) {
        guard let secs = sender.representedObject as? TimeInterval else { return }
        Config.saveWarningThreshold(secs)
        refreshSubmenuStates()
    }

    @objc private func toggleSound() {
        Config.saveSoundEnabled(!Config.soundEnabled)
        refreshSubmenuStates()
    }

    @objc private func openCalendarWindow() {
        onOpenWindow?()
    }

    // MARK: - Live countdown between polls

    private func scheduleRefreshTimer() {
        // Delay first fire until the next :00/:15/:30/:45 wall-clock second so
        // subsequent 15s ticks land on those boundaries and stay in sync.
        let comps = Calendar.current.dateComponents([.second, .nanosecond], from: Date())
        let secFrac = Double(comps.second ?? 0) + Double(comps.nanosecond ?? 0) / 1_000_000_000
        let delay = (floor(secFrac / 15) + 1) * 15 - secFrac

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.applyDisplay()
            self.refreshTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
                self?.applyDisplay()
            }
        }
    }
}
