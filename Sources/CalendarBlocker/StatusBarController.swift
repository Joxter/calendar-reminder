import AppKit

final class StatusBarController: NSObject {
    private let item: NSStatusItem
    private var nextEvent: CalEvent?
    private var refreshTimer: Timer?

    /// Called after the user saves a new calendar URL.
    var onURLChanged: (() -> Void)?
    /// Called when the user clicks "Open Calendar" in the menu.
    var onOpenWindow: (() -> Void)?

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
        let tint: NSColor
        let label: String

        if secs <= 0 {
            symbolName = "calendar.badge.clock"; tint = .systemRed;    label = "now"
        } else if secs < 5 * 60 {
            let m = max(1, Int(ceil(secs / 60)))
            symbolName = "calendar.badge.clock"; tint = .systemOrange; label = "\(m)m"
        } else if secs < .infinity {
            let m = Int(ceil(secs / 60))
            if m >= 60 {
                let h = m / 60, rm = m % 60
                label = rm > 0 ? "\(h)h \(rm)m" : "\(h)h"
            } else {
                label = "\(m)m"
            }
            symbolName = "calendar"; tint = .secondaryLabelColor
        } else {
            symbolName = "calendar"; tint = .secondaryLabelColor; label = ""
        }

        let cfg = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Calendar")?
            .withSymbolConfiguration(cfg)
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

        let urlItem = NSMenuItem(title: "Set Calendar URL…", action: #selector(setCalendarURL), keyEquivalent: ",")
        urlItem.target = self
        menu.addItem(urlItem)

        menu.addItem(.separator())

        menu.addItem(makePollIntervalMenu())
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

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        item.menu = menu
    }

    private func makePollIntervalMenu() -> NSMenuItem {
        let options: [(String, TimeInterval)] = [
            ("15 seconds", 15), ("30 seconds", 30), ("1 minute", 60), ("5 minutes", 300)
        ]
        let sub = NSMenu()
        for (title, secs) in options {
            let it = NSMenuItem(title: title, action: #selector(setPollInterval(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = secs as AnyObject
            it.state = Config.pollInterval == secs ? .on : .off
            sub.addItem(it)
        }
        let parent = NSMenuItem(title: "Check every", action: nil, keyEquivalent: "")
        parent.submenu = sub
        parent.tag = 10
        return parent
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

    private func refreshSubmenuStates() {
        if let pollMenu = item.menu?.item(withTag: 10)?.submenu {
            for it in pollMenu.items {
                it.state = (it.representedObject as? TimeInterval) == Config.pollInterval ? .on : .off
            }
        }
        if let warnMenu = item.menu?.item(withTag: 11)?.submenu {
            for it in warnMenu.items {
                it.state = (it.representedObject as? TimeInterval) == Config.warningThreshold ? .on : .off
            }
        }
        item.menu?.item(withTag: 99)?.state = Config.soundEnabled ? .on : .off
    }

    private func updateMenuEventItem() {
        guard let menuItem = item.menu?.item(withTag: 42) else { return }
        if let ev = nextEvent {
            let fmt = DateFormatter(); fmt.dateFormat = "HH:mm"
            menuItem.title = "\(ev.title)  ·  \(fmt.string(from: ev.start))"
        } else {
            menuItem.title = "No upcoming events today"
        }
    }

    @objc private func setCalendarURL() {
        let alert = NSAlert()
        alert.messageText = "Set Calendar URL"
        alert.informativeText = "Paste your Google Calendar private iCal URL (Settings → Secret address in iCal format):"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 440, height: 22))
        field.stringValue = UserDefaults.standard.string(forKey: "icalURL") ?? ""
        field.placeholderString = "https://calendar.google.com/calendar/ical/…/basic.ics"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let raw = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty, URL(string: raw) != nil else { return }
        Config.saveIcalURL(raw)
        onURLChanged?()
    }

    @objc private func setPollInterval(_ sender: NSMenuItem) {
        guard let secs = sender.representedObject as? TimeInterval else { return }
        Config.savePollInterval(secs)
        refreshSubmenuStates()
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
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.applyDisplay()
        }
    }
}
