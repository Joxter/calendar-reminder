import AppKit

// MARK: - Urgency accent colors (intentionally opaque — convey alertness state)
private let accentInProgress = NSColor(hex: "#ef4444")
private let accentImminent   = NSColor(hex: "#f97316")
private let accentSoon       = NSColor(hex: "#f59e0b")

// MARK: - Layout constants
private let axisH: CGFloat  = 20
private let badgeH: CGFloat = 16
private let lPad: CGFloat   = 10
private let rPad: CGFloat   = 10

// MARK: - Right-column font size — single knob that scales all timeline text
private let timelineFontSize: CGFloat = 13
private var rowH: CGFloat { timelineFontSize + 10 }  // row height tracks font size

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
        let hourFmt = DateFormatter(); hourFmt.dateFormat = "H"
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

            let lbl   = hourFmt.string(from: cur) as NSString
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
            let nowFmt = DateFormatter(); nowFmt.dateFormat = "HH:mm"
            let nowStr = nowFmt.string(from: now) as NSString
            let nowAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: timelineFontSize - 2, weight: .semibold),
                .foregroundColor: nowColor,
            ]
            let nowSz = nowStr.size(withAttributes: nowAttrs)
            nowStr.draw(at: NSPoint(x: nx + dotR + 3, y: (axisH - nowSz.height) / 2),
                        withAttributes: nowAttrs)
        }

        let overlaps = overlappingIndices(todayEvents)
        let timeFmt  = DateFormatter(); timeFmt.dateFormat = "HH:mm"

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
            let isFocused = focused.map { $0.title == ev.title && $0.start == ev.start } ?? false
            let color: NSColor
            if done                                  { color = .tertiaryLabelColor }
            else if isFocused                        { color = accent }
            else if ev.start <= now && now < ev.end  { color = .systemGreen }
            else if overlaps.contains(i)             { color = .systemOrange }
            else                                     { color = .systemBlue }
            let alpha: CGFloat = done ? 0.35 : 1

            let timeStr   = timeFmt.string(from: ev.start) as NSString
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

    init(event: CalEvent?, todayEvents: [CalEvent]) {
        self.event = event
        self.todayEvents = todayEvents

        let accent: NSColor = event.map { urgency($0).1 } ?? .tertiaryLabelColor
        let timelineH = axisH + CGFloat(max(todayEvents.count, 1)) * rowH + axisH
        let winH      = min(500, max(230, timelineH + 54) + 4)
        let winW: CGFloat = 720
        let screen = NSScreen.main!.frame
        let origin = NSPoint(x: (screen.width - winW) / 2, y: (screen.height - winH) / 2)

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
        if event != nil { NSSound.playSystemSound("Glass") }
    }

    // MARK: - UI

    private func buildUI(accent: NSColor, timelineH: CGFloat) {
        let root = NSView()
        root.wantsLayer = true
        contentView = root
        root.frame = contentView?.bounds ?? .zero
        root.autoresizingMask = [.width, .height]

        // Urgency accent stripe at top (hidden when no active event)
        let bar = NSView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.wantsLayer = true
        bar.layer?.backgroundColor = event != nil ? accent.cgColor : NSColor.clear.cgColor
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

        // Right column — solid white background
        let right = NSView()
        right.translatesAutoresizingMaskIntoConstraints = false
        right.wantsLayer = true
        right.layer?.backgroundColor = NSColor.white.cgColor
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

        if let event = event {
            buildLeftEvent(in: left, accent: accent, event: event)
        } else {
            buildLeftPlaceholder(in: left)
        }
        buildRight(in: right, timelineH: timelineH, accent: accent)
    }

    private func buildLeftEvent(in left: NSView, accent: NSColor, event: CalEvent) {
        let (badgeText, _) = urgency(event)
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
        titleField.font                    = NSFont.boldSystemFont(ofSize: 16)
        titleField.textColor               = .labelColor
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

    private func buildLeftPlaceholder(in left: NSView) {
        let pad: CGFloat = 18

        let heading = NSTextField(labelWithString: "No imminent meetings")
        heading.translatesAutoresizingMaskIntoConstraints = false
        heading.font      = NSFont.boldSystemFont(ofSize: 14)
        heading.textColor = .labelColor
        heading.lineBreakMode = .byWordWrapping
        heading.preferredMaxLayoutWidth = 210 - pad * 2
        left.addSubview(heading)

        let count = todayEvents.count
        let sub = NSTextField(labelWithString: count == 0
            ? "Nothing scheduled today"
            : "\(count) event\(count == 1 ? "" : "s") today")
        sub.translatesAutoresizingMaskIntoConstraints = false
        sub.font      = NSFont.systemFont(ofSize: 11)
        sub.textColor = .secondaryLabelColor
        left.addSubview(sub)

        let btn = NSButton(title: "Dismiss", target: self, action: #selector(dismiss))
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.bezelStyle    = .rounded
        btn.keyEquivalent = "\r"
        left.addSubview(btn)

        NSLayoutConstraint.activate([
            heading.leadingAnchor.constraint(equalTo: left.leadingAnchor, constant: pad),
            heading.trailingAnchor.constraint(equalTo: left.trailingAnchor, constant: -pad),
            heading.topAnchor.constraint(equalTo: left.topAnchor, constant: 24),

            sub.leadingAnchor.constraint(equalTo: left.leadingAnchor, constant: pad),
            sub.trailingAnchor.constraint(equalTo: left.trailingAnchor, constant: -pad),
            sub.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 6),

            btn.trailingAnchor.constraint(equalTo: left.trailingAnchor, constant: -pad),
            btn.bottomAnchor.constraint(equalTo: left.bottomAnchor, constant: -16),
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
        timeline.focused     = event
        timeline.accent      = accent
        right.addSubview(timeline)

        NSLayoutConstraint.activate([
            dateField.leadingAnchor.constraint(equalTo: right.leadingAnchor, constant: 12),
            dateField.topAnchor.constraint(equalTo: right.topAnchor, constant: 9),

            timeline.leadingAnchor.constraint(equalTo: right.leadingAnchor, constant: 4),
            timeline.trailingAnchor.constraint(equalTo: right.trailingAnchor, constant: -4),
            timeline.topAnchor.constraint(equalTo: dateField.bottomAnchor, constant: 6),
            timeline.heightAnchor.constraint(equalToConstant: timelineH),
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
