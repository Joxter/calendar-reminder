import AppKit

// MARK: - Urgency accent colors (intentionally opaque — convey alertness state)
private let accentInProgress = NSColor(hex: "#ef4444")
private let accentImminent   = NSColor(hex: "#f97316")
private let accentSoon       = NSColor(hex: "#f59e0b")

// MARK: - Layout constants (match Python version)
private let axisH: CGFloat    = 20
private let rowH: CGFloat     = 22
private let badgeW: CGFloat   = 40
private let badgeH: CGFloat   = 16
private let badgeR: CGFloat   = 3
private let lineH: CGFloat    = 2
private let lPad: CGFloat     = 10
private let rPad: CGFloat     = 10
private let fontSize: CGFloat = 11

// MARK: - Urgency

private func urgency(_ event: CalEvent) -> (String, NSColor) {
    let secs = event.startsInSeconds
    if secs <= 0   { return ("IN PROGRESS",                     accentInProgress) }
    if secs <= 120 {
        let m = Int(secs) / 60, s = Int(secs) % 60
        return ("STARTING IN \(m)m \(s)s",                      accentImminent)
    }
    return ("STARTING IN \(Int(secs) / 60) MIN",                accentSoon)
}

private func durString(_ event: CalEvent) -> String {
    let m = Int(event.duration / 60)
    guard m > 0 else { return "" }
    return "\(m / 60):\(String(format: "%02d", m % 60))"
}

private func overlappingIndices(_ events: [CalEvent]) -> Set<Int> {
    var result = Set<Int>()
    for i in events.indices {
        for j in (i+1)..<events.count {
            if events[i].start < events[j].end && events[j].start < events[i].end {
                result.insert(i); result.insert(j)
            }
        }
    }
    return result
}

// MARK: - Timeline View

final class TimelineView: NSView {
    var todayEvents: [CalEvent] = []
    var focused: CalEvent?
    var accent: NSColor = .systemBlue

    // y=0 at top, increasing downward — matches Python/tkinter exactly
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // No background fill — NSVisualEffectView parent (sidebar) shows through
        guard !todayEvents.isEmpty, let focused else { return }

        let now  = Date()
        let w    = bounds.width
        let barW = w - lPad - rPad

        let cal = Calendar.current
        var rs = cal.date(bySettingHour: 8,  minute: 0, second: 0, of: now)!
        var re = cal.date(bySettingHour: 18, minute: 0, second: 0, of: now)!
        if let first = todayEvents.first {
            rs = min(rs, cal.date(bySetting: .minute, value: 0, of: first.start)!)
        }
        if let last = todayEvents.last {
            re = max(re, cal.date(bySetting: .minute, value: 0, of: last.end)!)
        }

        let totSecs = max(re.timeIntervalSince(rs), 1)
        func t2x(_ t: Date) -> CGFloat {
            lPad + max(0, min(barW, CGFloat(t.timeIntervalSince(rs)) / CGFloat(totSecs) * barW))
        }

        let rowsH = CGFloat(todayEvents.count) * rowH + 6

        // Hour gridlines + axis labels
        var cur = rs
        let hourFmt = DateFormatter(); hourFmt.dateFormat = "H"
        while cur <= re {
            let x = t2x(cur)
            NSColor.separatorColor.setStroke()
            let grid = NSBezierPath()
            grid.move(to: NSPoint(x: x, y: axisH))
            grid.line(to: NSPoint(x: x, y: axisH + rowsH))
            grid.lineWidth = 0.5
            grid.stroke()

            let lbl      = hourFmt.string(from: cur) as NSString
            let lblAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 8),
                .foregroundColor: NSColor.tertiaryLabelColor,
            ]
            let lblSz = lbl.size(withAttributes: lblAttrs)
            lbl.draw(at: NSPoint(x: x - lblSz.width / 2, y: (axisH - lblSz.height) / 2),
                     withAttributes: lblAttrs)
            cur = cal.date(byAdding: .hour, value: 1, to: cur)!
        }

        // "Now" marker — subtle dashed line
        if now >= rs && now <= re {
            NSColor.systemRed.withAlphaComponent(0.4).setStroke()
            let nx     = t2x(now)
            let marker = NSBezierPath()
            marker.setLineDash([2, 4], count: 2, phase: 0)
            marker.move(to: NSPoint(x: nx, y: 0))
            marker.line(to: NSPoint(x: nx, y: axisH + rowsH))
            marker.stroke()
        }

        let overlaps = overlappingIndices(todayEvents)
        let timeFmt  = DateFormatter(); timeFmt.dateFormat = "HH:mm"

        for (i, ev) in todayEvents.enumerated() {
            // isFlipped=true: row 0 just below axis, same math as Python
            let cy = axisH + CGFloat(i) * rowH + rowH / 2
            let x1 = t2x(ev.start)
            let x2 = t2x(ev.end)

            let done      = ev.end   <= now
            let active    = ev.start <= now && now < ev.end
            let isFocused = ev.title == focused.title && ev.start == focused.start

            let color: NSColor
            if done                      { color = .tertiaryLabelColor }
            else if isFocused            { color = accent }
            else if active               { color = .systemGreen }
            else if overlaps.contains(i) { color = .systemOrange }
            else                         { color = .systemBlue }

            let bh2   = badgeH / 2
            let lineY = cy + bh2   // bottom of badge = top of underline

            // Duration underline (slightly transparent for done events)
            color.withAlphaComponent(done ? 0.35 : 0.7).setFill()
            NSBezierPath(rect: NSRect(x: x1, y: lineY, width: x2 - x1, height: lineH)).fill()

            // Badge: TL, TR, BL rounded; BR square (where underline connects)
            color.setFill()
            let by1 = cy - bh2
            let bx2 = x1 + badgeW
            NSBezierPath(roundedRect: NSRect(x: x1, y: by1, width: badgeW, height: badgeH),
                         xRadius: badgeR, yRadius: badgeR).fill()
            // Fill BR rounded curve to make it a square corner
            NSBezierPath(rect: NSRect(x: bx2 - badgeR, y: lineY - badgeR,
                                      width: badgeR, height: badgeR)).fill()

            // Badge time label — centered in badge
            let timeStr  = timeFmt.string(from: ev.start) as NSString
            let timeAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: fontSize),
                .foregroundColor: NSColor.white,
            ]
            let timeSz = timeStr.size(withAttributes: timeAttrs)
            timeStr.draw(at: NSPoint(x: x1 + (badgeW - timeSz.width) / 2,
                                     y: cy - timeSz.height / 2),
                         withAttributes: timeAttrs)

            // Title + duration — right of badge, left for events >= 13:00
            let dur      = durString(ev)
            let label    = dur.isEmpty ? ev.title : "\(ev.title)  \(dur)"
            let txtColor = done ? NSColor.tertiaryLabelColor : NSColor.labelColor
            let font     = isFocused ? NSFont.boldSystemFont(ofSize: fontSize) : NSFont.systemFont(ofSize: fontSize)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: txtColor]
            let ns = label as NSString
            let sz = ns.size(withAttributes: attrs)

            if Calendar.current.component(.hour, from: ev.start) >= 13 {
                ns.draw(at: NSPoint(x: x1 - 6 - sz.width, y: cy - sz.height / 2), withAttributes: attrs)
            } else {
                ns.draw(at: NSPoint(x: x1 + badgeW + 6, y: cy - sz.height / 2), withAttributes: attrs)
            }
        }
    }
}

// MARK: - Reminder Window

final class ReminderWindow: NSWindow {
    private let event: CalEvent
    private let todayEvents: [CalEvent]

    init(event: CalEvent, todayEvents: [CalEvent]) {
        self.event = event
        self.todayEvents = todayEvents

        let (_, accent) = urgency(event)
        let timelineH   = axisH + CGFloat(todayEvents.count) * rowH + 10
        let winH        = min(500, max(230, timelineH + 54) + 4)
        let winW: CGFloat = 720
        let screen = NSScreen.main!.frame
        let origin = NSPoint(x: (screen.width - winW) / 2, y: (screen.height - winH) / 2)

        super.init(
            contentRect: NSRect(origin: origin, size: NSSize(width: winW, height: winH)),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        title = "Meeting Reminder"
        isReleasedWhenClosed = false
        level = .floating
        isMovableByWindowBackground = true

        buildUI(accent: accent, timelineH: timelineH)
        NSSound.playSystemSound("Glass")
    }

    // MARK: - UI

    private func buildUI(accent: NSColor, timelineH: CGFloat) {
        let (badgeText, _) = urgency(event)

        let root = NSView()
        root.wantsLayer = true
        contentView = root
        root.frame = contentView?.bounds ?? .zero
        root.autoresizingMask = [.width, .height]

        // Urgency accent stripe at top
        let bar = NSView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.wantsLayer = true
        bar.layer?.backgroundColor = accent.cgColor
        root.addSubview(bar)

        // Left column — opaque, matches window background
        let left = NSVisualEffectView()
        left.translatesAutoresizingMaskIntoConstraints = false
        left.material      = .contentBackground
        left.blendingMode  = .withinWindow
        left.state         = .active
        root.addSubview(left)

        // Vertical separator
        let sepV = NSView()
        sepV.translatesAutoresizingMaskIntoConstraints = false
        sepV.wantsLayer = true
        sepV.layer?.backgroundColor = NSColor.separatorColor.cgColor
        root.addSubview(sepV)

        // Right column — frosted sidebar (like Finder sidebar, Notes)
        let right = NSVisualEffectView()
        right.translatesAutoresizingMaskIntoConstraints = false
        right.material     = .sidebar
        right.blendingMode = .behindWindow
        right.state        = .active
        root.addSubview(right)

        let leftW: CGFloat = 210
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: root.topAnchor),
            bar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            bar.heightAnchor.constraint(equalToConstant: 4),

            left.topAnchor.constraint(equalTo: bar.bottomAnchor),
            left.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            left.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            left.widthAnchor.constraint(equalToConstant: leftW),

            sepV.topAnchor.constraint(equalTo: bar.bottomAnchor),
            sepV.leadingAnchor.constraint(equalTo: left.trailingAnchor),
            sepV.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            sepV.widthAnchor.constraint(equalToConstant: 1),

            right.topAnchor.constraint(equalTo: bar.bottomAnchor),
            right.leadingAnchor.constraint(equalTo: sepV.trailingAnchor),
            right.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            right.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])

        buildLeft(in: left, accent: accent, badgeText: badgeText)
        buildRight(in: right, timelineH: timelineH, accent: accent)
    }

    private func buildLeft(in left: NSView, accent: NSColor, badgeText: String) {
        let pad: CGFloat = 18

        // Urgency pill
        let pill = NSView()
        pill.translatesAutoresizingMaskIntoConstraints = false
        pill.wantsLayer = true
        pill.layer?.backgroundColor = accent.cgColor
        pill.layer?.cornerRadius    = 4
        left.addSubview(pill)

        let pillLbl = NSTextField(labelWithString: badgeText)
        pillLbl.translatesAutoresizingMaskIntoConstraints = false
        pillLbl.font      = NSFont.boldSystemFont(ofSize: 9)
        pillLbl.textColor = .white
        pill.addSubview(pillLbl)

        // Event title
        let titleField = NSTextField(wrappingLabelWithString: event.title)
        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.font                   = NSFont.boldSystemFont(ofSize: 16)
        titleField.textColor              = .labelColor
        titleField.preferredMaxLayoutWidth = 210 - pad * 2
        left.addSubview(titleField)

        // Duration
        let dur      = durString(event)
        let durField = NSTextField(labelWithString: dur)
        durField.translatesAutoresizingMaskIntoConstraints = false
        durField.font      = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        durField.textColor = .secondaryLabelColor
        durField.isHidden  = dur.isEmpty
        left.addSubview(durField)

        // Dismiss — native default button (system accent color, activated by Return)
        let btn = NSButton(title: "Dismiss", target: self, action: #selector(dismiss))
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.bezelStyle    = .rounded
        btn.keyEquivalent = "\r"
        left.addSubview(btn)

        NSLayoutConstraint.activate([
            pillLbl.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 8),
            pillLbl.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -8),
            pillLbl.topAnchor.constraint(equalTo: pill.topAnchor, constant: 2),
            pillLbl.bottomAnchor.constraint(equalTo: pill.bottomAnchor, constant: -2),

            pill.leadingAnchor.constraint(equalTo: left.leadingAnchor, constant: pad),
            pill.topAnchor.constraint(equalTo: left.topAnchor, constant: 16),

            titleField.leadingAnchor.constraint(equalTo: left.leadingAnchor, constant: pad),
            titleField.trailingAnchor.constraint(equalTo: left.trailingAnchor, constant: -pad),
            titleField.topAnchor.constraint(equalTo: pill.bottomAnchor, constant: 10),

            durField.leadingAnchor.constraint(equalTo: left.leadingAnchor, constant: pad),
            durField.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 4),

            btn.trailingAnchor.constraint(equalTo: left.trailingAnchor, constant: -pad),
            btn.bottomAnchor.constraint(equalTo: left.bottomAnchor, constant: -16),
        ])
    }

    private func buildRight(in right: NSView, timelineH: CGFloat, accent: NSColor) {
        // Date header
        let fmt       = DateFormatter(); fmt.dateFormat = "EEEE, MMM d"
        let dateField = NSTextField(labelWithString: fmt.string(from: Date()))
        dateField.translatesAutoresizingMaskIntoConstraints = false
        dateField.font      = NSFont.boldSystemFont(ofSize: 11)
        dateField.textColor = .secondaryLabelColor
        right.addSubview(dateField)

        // Separator below date
        let hSep = NSView()
        hSep.translatesAutoresizingMaskIntoConstraints = false
        hSep.wantsLayer = true
        hSep.layer?.backgroundColor = NSColor.separatorColor.cgColor
        right.addSubview(hSep)

        // Timeline — transparent background, sidebar vibrancy shows through
        let timeline = TimelineView()
        timeline.translatesAutoresizingMaskIntoConstraints = false
        timeline.todayEvents = todayEvents
        timeline.focused     = event
        timeline.accent      = accent
        right.addSubview(timeline)

        // Remaining event count — subtle footer
        let remaining = todayEvents.filter {
            $0.start > Date() && !($0.title == event.title && $0.start == event.start)
        }.count
        let countLbl = NSTextField(labelWithString:
            remaining > 0 ? "\(remaining) more event\(remaining == 1 ? "" : "s") today" : "")
        countLbl.translatesAutoresizingMaskIntoConstraints = false
        countLbl.font      = NSFont.systemFont(ofSize: 10)
        countLbl.textColor = .tertiaryLabelColor
        countLbl.isHidden  = remaining == 0
        right.addSubview(countLbl)

        NSLayoutConstraint.activate([
            dateField.leadingAnchor.constraint(equalTo: right.leadingAnchor, constant: 12),
            dateField.topAnchor.constraint(equalTo: right.topAnchor, constant: 9),

            hSep.leadingAnchor.constraint(equalTo: right.leadingAnchor, constant: 12),
            hSep.trailingAnchor.constraint(equalTo: right.trailingAnchor, constant: -12),
            hSep.topAnchor.constraint(equalTo: dateField.bottomAnchor, constant: 1),
            hSep.heightAnchor.constraint(equalToConstant: 1),

            timeline.leadingAnchor.constraint(equalTo: right.leadingAnchor, constant: 4),
            timeline.trailingAnchor.constraint(equalTo: right.trailingAnchor, constant: -4),
            timeline.topAnchor.constraint(equalTo: hSep.bottomAnchor, constant: 4),
            timeline.heightAnchor.constraint(equalToConstant: timelineH),

            countLbl.trailingAnchor.constraint(equalTo: right.trailingAnchor, constant: -12),
            countLbl.bottomAnchor.constraint(equalTo: right.bottomAnchor, constant: -10),
        ])
    }

    @objc private func dismiss() { close() }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { close() }   // Esc; Return is handled by button keyEquivalent
        else { super.keyDown(with: event) }
    }
}

// MARK: - Helpers

extension NSColor {
    convenience init(hex: String) {
        let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        var rgb: UInt64 = 0; Scanner(string: h).scanHexInt64(&rgb)
        self.init(
            red:   CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8)  & 0xFF) / 255,
            blue:  CGFloat( rgb        & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension NSSound {
    static func playSystemSound(_ name: String) {
        NSSound(named: name)?.play()
    }
}
