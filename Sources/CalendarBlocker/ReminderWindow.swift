import AppKit

// MARK: - Urgency accent colors
private let accentInProgress = NSColor(hex: "#dc2626")  // red
private let accentImminent   = NSColor(hex: "#7c3aed")  // purple
private let accentSoon       = NSColor(hex: "#2563eb")  // blue

// MARK: - Layout constants
private let axisH: CGFloat  = 20
private let badgeH: CGFloat = 16
private let lPad: CGFloat   = 10
private let rPad: CGFloat   = 10

// MARK: - Right-column font size — single knob that scales all timeline text
private let timelineFontSize: CGFloat = 13
private var rowH: CGFloat { timelineFontSize + 10 }  // row height tracks font size

// MARK: - Left panel spacing
private let gapNextToTitle: CGFloat  =  0   // "NEXT" label to event title
private let gapTitleToTimer: CGFloat = -1   // event title to countdown timer (slight visual tuck)

// MARK: - L-shape style
private let shapeStrokeW: CGFloat  = 2   // thickness of the L stroke
private let shapeCornerR: CGFloat  = 4   // corner curviness (0 = sharp, max = badgeH/2 = 8)

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


// MARK: - Timeline View

final class TimelineView: NSView {
    var todayEvents: [CalEvent] = []
    var focused: CalEvent?
    var accent: NSColor = .systemBlue
    var onEventSelected: ((CalEvent) -> Void)?

    // y=0 at top, increasing downward — matches Python/tkinter exactly
    override var isFlipped: Bool { true }

    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        let row = Int((loc.y - axisH) / rowH)
        guard row >= 0, row < todayEvents.count else { return }
        onEventSelected?(todayEvents[row])
    }

    override func resetCursorRects() {
        for i in todayEvents.indices {
            let y = axisH + CGFloat(i) * rowH
            addCursorRect(NSRect(x: 0, y: y, width: bounds.width, height: rowH), cursor: .pointingHand)
        }
    }

    private static let hourFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "H";     return f }()
    private static let timeFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f }()

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // No background fill — NSVisualEffectView parent (sidebar) shows through
        guard !todayEvents.isEmpty else { return }

        let now  = Config.now
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

        // Hour gridlines + axis labels (labels at bottom)
        var cur = rs
        let lblAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: timelineFontSize - 2, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let bottomY = axisH + rowsH  // top of bottom label area
        while cur <= re {
            let x = t2x(cur)
            NSColor.separatorColor.setStroke()
            let grid = NSBezierPath()
            grid.move(to: NSPoint(x: x, y: axisH))   // start below the top strip
            grid.line(to: NSPoint(x: x, y: bottomY))
            grid.lineWidth = 0.5
            grid.stroke()

            let lbl   = TimelineView.hourFmt.string(from: cur) as NSString
            let lblSz = lbl.size(withAttributes: lblAttrs)
            lbl.draw(at: NSPoint(x: x - lblSz.width / 2, y: bottomY + (axisH - lblSz.height) / 2),
                     withAttributes: lblAttrs)
            cur = cal.date(byAdding: .hour, value: 1, to: cur)!
        }

        // "Now" marker — dot + time label at top, solid line through rows
        if now >= rs && now <= re {
            let nx       = t2x(now)
            let dotR: CGFloat = 3
            let nowColor = NSColor.systemRed

            // Solid line from dot centre down through the rows
            nowColor.withAlphaComponent(0.5).setStroke()
            let line = NSBezierPath()
            line.move(to: NSPoint(x: nx, y: axisH / 2))
            line.line(to: NSPoint(x: nx, y: bottomY))
            line.lineWidth = 1
            line.stroke()

            // Filled dot
            nowColor.setFill()
            NSBezierPath(ovalIn: NSRect(x: nx - dotR, y: (axisH - dotR * 2) / 2,
                                        width: dotR * 2, height: dotR * 2)).fill()

            // Current time label — right of dot, vertically centred in top strip
            let nowStr = TimelineView.timeFmt.string(from: now) as NSString
            let nowAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: timelineFontSize - 2, weight: .semibold),
                .foregroundColor: nowColor,
            ]
            let nowSz = nowStr.size(withAttributes: nowAttrs)
            nowStr.draw(at: NSPoint(x: nx + dotR + 3, y: (axisH - nowSz.height) / 2),
                        withAttributes: nowAttrs)
        }

        // Precompute per-event layout so we can use it across passes
        struct EvLayout {
            let cy: CGFloat, x1: CGFloat, x2: CGFloat
            let color: NSColor, alpha: CGFloat
            let timeStr: NSString, timeAttrs: [NSAttributedString.Key: Any]
            let timeSz: NSSize, timeOrigin: NSPoint
            let titleStr: NSString, titleAttrs: [NSAttributedString.Key: Any]
            let titleSz: NSSize, titleOrigin: NSPoint
        }
        var layouts: [EvLayout] = []
        for (i, ev) in todayEvents.enumerated() {
            let cy = axisH + CGFloat(i) * rowH + rowH / 2
            let x1 = t2x(ev.start), x2 = t2x(ev.end)
            let done      = ev.end   <= now
            let isFocused = focused == ev
            let color: NSColor
            if done                                  { color = .tertiaryLabelColor }
            else if ev.start <= now && now < ev.end  { color = .systemGreen }
            else                                     { color = .systemBlue }
            let alpha: CGFloat = done ? 0.35 : 1

            let timeStr   = TimelineView.timeFmt.string(from: ev.start) as NSString
            let timeAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: timelineFontSize),
                .foregroundColor: color.withAlphaComponent(alpha),
            ]
            let timeSz     = timeStr.size(withAttributes: timeAttrs)
            let timeOrigin = NSPoint(x: x1 + shapeStrokeW / 2 + 2, y: cy - timeSz.height / 2)

            let txtColor   = done ? NSColor.tertiaryLabelColor : NSColor.labelColor
            let font       = isFocused ? NSFont.boldSystemFont(ofSize: timelineFontSize) : NSFont.systemFont(ofSize: timelineFontSize)
            let titleAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: txtColor]
            let titleStr   = ev.title as NSString
            let titleSz    = titleStr.size(withAttributes: titleAttrs)
            let titleX: CGFloat = Calendar.current.component(.hour, from: ev.start) >= 13
                ? x1 - 6 - titleSz.width
                : x1 + shapeStrokeW / 2 + 4 + timeSz.width + 6
            let titleOrigin = NSPoint(x: titleX, y: cy - titleSz.height / 2)

            layouts.append(EvLayout(cy: cy, x1: x1, x2: x2, color: color, alpha: alpha,
                                    timeStr: timeStr, timeAttrs: timeAttrs,
                                    timeSz: timeSz, timeOrigin: timeOrigin,
                                    titleStr: titleStr, titleAttrs: titleAttrs,
                                    titleSz: titleSz, titleOrigin: titleOrigin))
        }

        // Pass 1: white backgrounds behind text
        NSColor.white.setFill()
        for l in layouts {
            NSBezierPath(rect: NSRect(origin: l.timeOrigin,  size: l.timeSz).insetBy(dx: -2, dy: 0)).fill()
            NSBezierPath(rect: NSRect(origin: l.titleOrigin, size: l.titleSz).insetBy(dx: -2, dy: 0)).fill()
        }

        // Pass 2: L-shapes on top of white backgrounds
        for l in layouts {
            let bh2  = badgeH / 2
            let r    = min(shapeCornerR, bh2)
            let ox: CGFloat = -1   // nudge left
            let oy: CGFloat =  1   // nudge down
            let x1   = l.x1 + ox
            let botY = l.cy + bh2 + oy
            let path = NSBezierPath()
            path.move(to: NSPoint(x: x1, y: l.cy - bh2 + oy))
            path.line(to: NSPoint(x: x1, y: botY - r))
            path.appendArc(withCenter: NSPoint(x: x1 + r, y: botY - r),
                           radius: r, startAngle: 180, endAngle: 90, clockwise: true)
            path.line(to: NSPoint(x: l.x2 + ox, y: botY))
            path.lineWidth    = shapeStrokeW
            path.lineCapStyle = .round
            l.color.withAlphaComponent(l.alpha).setStroke()
            path.stroke()
        }

        // Pass 3: text on top of everything
        for l in layouts {
            l.timeStr.draw(at:  l.timeOrigin,  withAttributes: l.timeAttrs)
            l.titleStr.draw(at: l.titleOrigin, withAttributes: l.titleAttrs)
        }
    }
}

// MARK: - Reminder Window

final class ReminderWindow: NSWindow {
    private let event: CalEvent?
    private let todayEvents: [CalEvent]

    private var countdownField: NSTextField?
    private var countdownColor = NSColor.white
    private var colonVisible   = true
    private var tickTimer: Timer?

    private var leftColumn: NSView?
    private var timelineView: TimelineView?
    private var detailContainer: NSView?
    private var selectedEvent: CalEvent?
    private var accentColor: NSColor = NSColor(hex: "#475569")

    init(event: CalEvent?, todayEvents: [CalEvent]) {
        self.event = event
        self.todayEvents = todayEvents

        let accent: NSColor = event.map { urgency($0).1 } ?? NSColor(hex: "#475569")
        let timelineH = axisH + CGFloat(max(todayEvents.count, 1)) * rowH + axisH
        let winH      = min(500, max(230, timelineH + 54) + 4)
        let winW: CGFloat = 720
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(x: (screenFrame.width - winW) / 2, y: (screenFrame.height - winH) / 2)

        super.init(
            contentRect: NSRect(origin: origin, size: NSSize(width: winW, height: winH)),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        title = event != nil ? "Meeting Reminder" : "Calendar"
        isReleasedWhenClosed = false
        level = .floating
        isMovableByWindowBackground = true

        buildUI(accent: accent, timelineH: timelineH)
        if event != nil {
            if Config.soundEnabled { NSSound.playSystemSound("Glass") }
            startTickTimer()
        }
    }

    // MARK: - UI

    private func buildUI(accent: NSColor, timelineH: CGFloat) {
        let root = NSView()
        root.wantsLayer = true
        contentView = root
        root.frame = contentView?.bounds ?? .zero
        root.autoresizingMask = [.width, .height]

        // Left column — solid accent color
        let left = NSView()
        left.translatesAutoresizingMaskIntoConstraints = false
        left.wantsLayer = true
        left.layer?.backgroundColor = accent.cgColor
        root.addSubview(left)

        // Right column — solid white
        let right = NSView()
        right.translatesAutoresizingMaskIntoConstraints = false
        right.wantsLayer = true
        right.layer?.backgroundColor = NSColor.white.cgColor
        root.addSubview(right)

        let leftW: CGFloat = 210
        NSLayoutConstraint.activate([
            left.topAnchor.constraint(equalTo: root.topAnchor),
            left.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            left.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            left.widthAnchor.constraint(equalToConstant: leftW),

            right.topAnchor.constraint(equalTo: root.topAnchor),
            right.leadingAnchor.constraint(equalTo: left.trailingAnchor),
            right.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            right.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])

        self.leftColumn  = left
        self.accentColor = accent

        if let event = event {
            buildLeftEvent(in: left, accent: accent, event: event)
        } else {
            buildLeftPlaceholder(in: left)
        }
        buildRight(in: right, timelineH: timelineH, accent: accent)
    }

    private func buildLeftEvent(in left: NSView, accent: NSColor, event: CalEvent) {
        let pad: CGFloat = 16
        let white = NSColor.white

        // "NEXT" label
        let nextLbl = NSTextField(labelWithString: "NEXT")
        nextLbl.translatesAutoresizingMaskIntoConstraints = false
        nextLbl.font      = NSFont.boldSystemFont(ofSize: 9)
        nextLbl.textColor = white.withAlphaComponent(0.9)
        left.addSubview(nextLbl)

        // Event title
        let titleField = NSTextField(wrappingLabelWithString: event.title)
        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.font                    = NSFont.boldSystemFont(ofSize: 15)
        titleField.textColor               = white.withAlphaComponent(0.9)
        titleField.preferredMaxLayoutWidth = 210 - pad * 2
        left.addSubview(titleField)

        // Big countdown timer — the main focus
        let secs = event.startsInSeconds
        let timerText: String
        if secs <= 0 {
            timerText = "NOW"
        } else {
            let totalMin = Int(secs) / 60
            if totalMin >= 60 {
                let h = totalMin / 60, m = totalMin % 60
                timerText = String(format: "%d:%02d", h, m)
            } else {
                let m = totalMin, s = Int(secs) % 60
                timerText = String(format: "%02d:%02d", m, s)
            }
        }
        let timerField = NSTextField(labelWithString: timerText)
        timerField.translatesAutoresizingMaskIntoConstraints = false
        timerField.font      = NSFont.monospacedDigitSystemFont(ofSize: 52, weight: .black)
        timerField.textColor = white
        left.addSubview(timerField)
        countdownColor = white
        self.countdownField = timerField

        // Everything pinned to the bottom, gaps controlled by gapNextToTitle / gapTitleToTimer
        NSLayoutConstraint.activate([
            timerField.leadingAnchor.constraint(equalTo: left.leadingAnchor, constant: pad - 4),
            timerField.trailingAnchor.constraint(equalTo: left.trailingAnchor, constant: -pad),
            timerField.bottomAnchor.constraint(equalTo: left.bottomAnchor, constant: -pad),

            titleField.leadingAnchor.constraint(equalTo: left.leadingAnchor, constant: pad),
            titleField.trailingAnchor.constraint(equalTo: left.trailingAnchor, constant: -pad),
            titleField.bottomAnchor.constraint(equalTo: timerField.topAnchor, constant: -gapTitleToTimer),

            nextLbl.leadingAnchor.constraint(equalTo: left.leadingAnchor, constant: pad),
            nextLbl.bottomAnchor.constraint(equalTo: titleField.topAnchor, constant: -gapNextToTitle),
        ])
    }

    private func buildLeftPlaceholder(in left: NSView) {
        let pad: CGFloat = 18

        let heading = NSTextField(labelWithString: "All clear")
        heading.translatesAutoresizingMaskIntoConstraints = false
        heading.font      = NSFont.boldSystemFont(ofSize: 15)
        heading.textColor = NSColor.white
        heading.lineBreakMode = .byWordWrapping
        heading.preferredMaxLayoutWidth = 210 - pad * 2
        left.addSubview(heading)

        let count = todayEvents.count
        let sub = NSTextField(labelWithString: count == 0
            ? "Nothing scheduled today"
            : "\(count) event\(count == 1 ? "" : "s") today")
        sub.translatesAutoresizingMaskIntoConstraints = false
        sub.font      = NSFont.systemFont(ofSize: 12)
        sub.textColor = NSColor.white.withAlphaComponent(0.7)
        left.addSubview(sub)

        NSLayoutConstraint.activate([
            heading.leadingAnchor.constraint(equalTo: left.leadingAnchor, constant: pad),
            heading.trailingAnchor.constraint(equalTo: left.trailingAnchor, constant: -pad),
            heading.topAnchor.constraint(equalTo: left.topAnchor, constant: 24),

            sub.leadingAnchor.constraint(equalTo: left.leadingAnchor, constant: pad),
            sub.trailingAnchor.constraint(equalTo: left.trailingAnchor, constant: -pad),
            sub.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 6),
        ])
    }

    private func buildRight(in right: NSView, timelineH: CGFloat, accent: NSColor) {
        // Date header
        let fmt       = DateFormatter(); fmt.dateFormat = "EEEE, MMM d"
        let dateField = NSTextField(labelWithString: fmt.string(from: Config.now))
        dateField.translatesAutoresizingMaskIntoConstraints = false
        dateField.font      = NSFont.boldSystemFont(ofSize: timelineFontSize + 2)
        dateField.textColor = .labelColor
        right.addSubview(dateField)

        // Timeline
        let timeline = TimelineView()
        timeline.translatesAutoresizingMaskIntoConstraints = false
        timeline.todayEvents = todayEvents
        timeline.focused     = nil
        timeline.accent      = accent
        timeline.onEventSelected = { [weak self] ev in self?.handleTimelineEventSelected(ev) }
        right.addSubview(timeline)
        self.timelineView = timeline

        NSLayoutConstraint.activate([
            dateField.leadingAnchor.constraint(equalTo: right.leadingAnchor, constant: 12),
            dateField.topAnchor.constraint(equalTo: right.topAnchor, constant: 9),

            timeline.leadingAnchor.constraint(equalTo: right.leadingAnchor, constant: 4),
            timeline.trailingAnchor.constraint(equalTo: right.trailingAnchor, constant: -4),
            timeline.topAnchor.constraint(equalTo: dateField.bottomAnchor, constant: 6),
            timeline.heightAnchor.constraint(equalToConstant: timelineH),
        ])
    }

    // MARK: - Timeline event selection

    private func handleTimelineEventSelected(_ ev: CalEvent) {
        guard let left = leftColumn else { return }

        // Toggle: re-clicking the selected event deselects
        if selectedEvent == ev {
            selectedEvent = nil
            timelineView?.focused = nil
            timelineView?.needsDisplay = true
            detailContainer?.removeFromSuperview()
            detailContainer = nil
            if event == nil { buildLeftPlaceholder(in: left) }
            return
        }

        selectedEvent = ev
        timelineView?.focused = ev
        timelineView?.needsDisplay = true

        // Remove previous detail and, in browse mode, the placeholder (it's top-pinned)
        detailContainer?.removeFromSuperview()
        if event == nil { left.subviews.forEach { $0.removeFromSuperview() } }

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        left.addSubview(container)
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: left.topAnchor),
            container.leadingAnchor.constraint(equalTo: left.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: left.trailingAnchor),
        ])
        buildDetailContent(in: container, event: ev)
        detailContainer = container
    }

    private func buildDetailContent(in view: NSView, event: CalEvent) {
        let pad: CGFloat = 16
        let white = NSColor.white

        let timeFmt = DateFormatter(); timeFmt.dateFormat = "HH:mm"
        let timeStr = "\(timeFmt.string(from: event.start)) – \(timeFmt.string(from: event.end))"

        let totalMin = Int(event.duration / 60)
        let durStr: String = {
            guard totalMin > 0 else { return "" }
            let h = totalMin / 60, m = totalMin % 60
            return h > 0 ? (m > 0 ? "\(h)h \(m)m" : "\(h)h") : "\(m)m"
        }()

        var topAnchor: NSLayoutYAxisAnchor = view.topAnchor
        var topConstant: CGFloat = pad

        if let name = event.calendarName {
            let calLabel = NSTextField(labelWithString: name)
            calLabel.translatesAutoresizingMaskIntoConstraints = false
            calLabel.font          = NSFont.systemFont(ofSize: 10, weight: .medium)
            calLabel.textColor     = white.withAlphaComponent(0.55)
            calLabel.lineBreakMode = .byTruncatingTail
            view.addSubview(calLabel)
            NSLayoutConstraint.activate([
                calLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: pad),
                calLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: pad),
                calLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -pad),
            ])
            topAnchor = calLabel.bottomAnchor
            topConstant = 4
        }

        let titleField = NSTextField(wrappingLabelWithString: event.title)
        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.font                    = NSFont.boldSystemFont(ofSize: 15)
        titleField.textColor               = white
        titleField.preferredMaxLayoutWidth = 210 - pad * 2
        view.addSubview(titleField)

        let infoStr = durStr.isEmpty ? timeStr : "\(timeStr)  ·  \(durStr)"
        let infoField = NSTextField(labelWithString: infoStr)
        infoField.translatesAutoresizingMaskIntoConstraints = false
        infoField.font          = NSFont.systemFont(ofSize: 11)
        infoField.textColor     = white.withAlphaComponent(0.7)
        infoField.lineBreakMode = .byTruncatingTail
        view.addSubview(infoField)

        let linkBtn = NSButton(frame: .zero)
        linkBtn.translatesAutoresizingMaskIntoConstraints = false
        linkBtn.isBordered = false
        linkBtn.alignment  = .left
        linkBtn.attributedTitle = NSAttributedString(string: "Open in Calendar →", attributes: [
            .foregroundColor: white.withAlphaComponent(0.85),
            .underlineStyle:  NSUnderlineStyle.single.rawValue,
            .font:            NSFont.systemFont(ofSize: 11),
        ])
        linkBtn.target = self
        linkBtn.action = #selector(openSelectedEventInCalendar)
        view.addSubview(linkBtn)

        NSLayoutConstraint.activate([
            titleField.topAnchor.constraint(equalTo: topAnchor, constant: topConstant),
            titleField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: pad),
            titleField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -pad),

            infoField.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 6),
            infoField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: pad),
            infoField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),

            linkBtn.topAnchor.constraint(equalTo: infoField.bottomAnchor, constant: 10),
            linkBtn.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: pad),

            view.bottomAnchor.constraint(equalTo: linkBtn.bottomAnchor, constant: pad),
        ])
    }

    @objc private func openSelectedEventInCalendar() {
        guard let ev = selectedEvent else { return }
        NSWorkspace.shared.open(googleCalendarURL(for: ev))
    }

    private func googleCalendarURL(for ev: CalEvent) -> URL {
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: ev.start)
        let y = comps.year!, mo = comps.month!, d = comps.day!
        let email = ev.calendarEmail ?? ""

        // Use UID to construct a direct event link (Google Calendar iCal UIDs end in @google.com)
        if let uid = ev.uid, uid.lowercased().hasSuffix("@google.com"), !email.isEmpty {
            let eventId = String(uid.dropLast("@google.com".count)).lowercased()
            if !eventId.isEmpty {
                let combined = "\(eventId) \(email.lowercased())"
                let eid = Data(combined.utf8).base64EncodedString()
                    .replacingOccurrences(of: "+", with: "-")
                    .replacingOccurrences(of: "/", with: "_")
                    .replacingOccurrences(of: "=", with: "")
                if let url = URL(string: "https://www.google.com/calendar/event?eid=\(eid)") {
                    return url
                }
            }
        }

        // Fall back to day view with authuser hint so the right account is pre-selected
        var str = "https://calendar.google.com/calendar/r/day/\(y)/\(mo)/\(d)"
        if !email.isEmpty { str += "?authuser=\(email)" }
        return URL(string: str)!
    }

    private func startTickTimer() {
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        guard let event = event, let field = countdownField else { return }
        colonVisible.toggle()
        let secs = max(0, event.startsInSeconds)
        let text: String
        if secs <= 0 {
            text = "NOW"
        } else {
            let totalMin = Int(secs) / 60
            if totalMin >= 60 {
                let h = totalMin / 60, m = totalMin % 60
                text = String(format: "%d:%02d", h, m)
            } else {
                let m = totalMin, s = Int(secs) % 60
                text = String(format: "%02d:%02d", m, s)
            }
        }
        let font = NSFont.monospacedDigitSystemFont(ofSize: 52, weight: .black)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: countdownColor]
        let attributed = NSMutableAttributedString(string: text, attributes: attrs)
        if let colonRange = text.range(of: ":") {
            let nsRange = NSRange(colonRange, in: text)
            attributed.addAttribute(.foregroundColor,
                                    value: countdownColor.withAlphaComponent(colonVisible ? 1 : 0),
                                    range: nsRange)
        }
        field.attributedStringValue = attributed
    }

    override func close() {
        tickTimer?.invalidate()
        tickTimer = nil
        super.close()
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
