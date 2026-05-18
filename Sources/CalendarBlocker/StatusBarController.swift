import AppKit

final class StatusBarController: NSObject {
    private let item: NSStatusItem
    private var nextEvent: CalEvent?
    private var refreshTimer: Timer?

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

        let calItem = NSMenuItem(title: "Open Google Calendar", action: #selector(openCalendar), keyEquivalent: "")
        calItem.target = self
        menu.addItem(calItem)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        item.menu = menu
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

    @objc private func openCalendar() {
        NSWorkspace.shared.open(URL(string: "https://calendar.google.com")!)
    }

    // MARK: - Live countdown between polls

    private func scheduleRefreshTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.applyDisplay()
        }
    }
}
