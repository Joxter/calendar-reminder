import AppKit

// MARK: - Colors
private let leftBG   = NSColor(hex: "#ffffff")
private let rightBG  = NSColor(hex: "#f5f5f7")
private let pri      = NSColor(hex: "#1d1d1f")
private let sec      = NSColor(hex: "#86868b")
private let dim      = NSColor(hex: "#c7c7cc")
private let sep      = NSColor(hex: "#e5e5ea")
private let green    = NSColor(hex: "#34c759")
private let orange   = NSColor(hex: "#ff9f0a")
private let blue     = NSColor(hex: "#007aff")

// MARK: - Layout constants (match Python version)
private let axisH: CGFloat  = 20
private let rowH: CGFloat   = 22
private let badgeW: CGFloat = 40
private let badgeH: CGFloat = 16
private let badgeR: CGFloat = 3
private let lineH: CGFloat  = 2
private let lPad: CGFloat   = 10
private let rPad: CGFloat   = 10
private let fontSize: CGFloat = 11

// MARK: - Urgency

private func urgency(_ event: CalEvent) -> (String, NSColor) {
    let secs = event.startsInSeconds
    if secs <= 0      { return ("IN PROGRESS",                         NSColor(hex: "#ef4444")) }
    if secs <= 120    {
        let m = Int(secs) / 60, s = Int(secs) % 60
        return ("STARTING IN \(m)m \(s)s",                             NSColor(hex: "#f97316"))
    }
    return ("STARTING IN \(Int(secs) / 60) MIN",                       NSColor(hex: "#f59e0b"))
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
    var accent: NSColor = blue

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        rightBG.setFill()
        dirtyRect.fill()
        guard !todayEvents.isEmpty, let focused else { return }

        let now = Date()
        let w = bounds.width
        let barW = w - lPad - rPad

        // Time range: 8–18 local, extended for early/late events
        let cal = Calendar.current
        var rs = cal.date(bySettingHour: 8,  minute: 0, second: 0, of: now)!
        var re = cal.date(bySettingHour: 18, minute: 0, second: 0, of: now)!
        if let first = todayEvents.first { rs = min(rs, cal.date(bySetting: .minute, value: 0, of: first.start)!) }
        if let last  = todayEvents.last  { re = max(re, cal.date(bySetting: .minute, value: 0, of: last.end)!) }

        let totSecs = max(re.timeIntervalSince(rs), 1)
        func t2x(_ t: Date) -> CGFloat { lPad + max(0, min(barW, CGFloat(t.timeIntervalSince(rs)) / CGFloat(totSecs) * barW)) }

        let rowsH = CGFloat(todayEvents.count) * rowH + 6

        // Hour gridlines + axis labels
        var cur = rs
        let hourFmt = DateFormatter(); hourFmt.dateFormat = "H"
        while cur <= re {
            let x = t2x(cur)
            NSColor(hex: "#ebebeb").setStroke()
            let line = NSBezierPath(); line.move(to: NSPoint(x: x, y: axisH)); line.line(to: NSPoint(x: x, y: axisH + rowsH)); line.stroke()
            let lbl = hourFmt.string(from: cur) as NSString
            lbl.draw(at: NSPoint(x: x - 5, y: bounds.height - axisH + 2),
                     withAttributes: [.font: NSFont.systemFont(ofSize: 8), .foregroundColor: dim])
            cur = cal.date(byAdding: .hour, value: 1, to: cur)!
        }

        // "Now" marker
        if now >= rs && now <= re {
            NSColor(hex: "#ffb3af").setStroke()
            let nx = t2x(now)
            let marker = NSBezierPath()
            marker.setLineDash([2, 5], count: 2, phase: 0)
            marker.move(to: NSPoint(x: nx, y: 0)); marker.line(to: NSPoint(x: nx, y: axisH + rowsH))
            marker.stroke()
        }

        let overlaps = overlappingIndices(todayEvents)
        let timeFmt = DateFormatter(); timeFmt.dateFormat = "HH:mm"

        for (i, ev) in todayEvents.enumerated() {
            // In AppKit, y=0 is bottom — row 0 is topmost visually, so flip
            let cy = bounds.height - axisH - CGFloat(i) * rowH - rowH / 2
            let x1 = t2x(ev.start)
            let x2 = t2x(ev.end)

            let done      = ev.end   <= now
            let active    = ev.start <= now && now < ev.end
            let isFocused = ev.title == focused.title && ev.start == focused.start

            let color: NSColor
            if done           { color = NSColor(hex: "#6e6e73") }
            else if isFocused { color = accent }
            else if active    { color = green }
            else if overlaps.contains(i) { color = orange }
            else              { color = blue }

            let bh2    = badgeH / 2
            let lineY  = cy - bh2   // underline at badge bottom (AppKit y-up)

            // Duration underline
            color.setFill()
            NSBezierPath(rect: NSRect(x: x1, y: lineY - lineH, width: x2 - x1, height: lineH)).fill()

            // Badge with rounded corners (BR square)
            let badgePath = NSBezierPath()
            let bx1 = x1, bx2 = x1 + badgeW, by1 = lineY - badgeH, by2 = lineY
            badgePath.move(to: NSPoint(x: bx1, y: by1 + badgeR))
            badgePath.appendArc(withCenter: NSPoint(x: bx1 + badgeR, y: by1 + badgeR), radius: badgeR, startAngle: 180, endAngle: 270)
            badgePath.line(to: NSPoint(x: bx2,        y: by1))  // BR square
            badgePath.line(to: NSPoint(x: bx2,        y: by2 - badgeR))
            badgePath.appendArc(withCenter: NSPoint(x: bx2 - badgeR, y: by2 - badgeR), radius: badgeR, startAngle: 0, endAngle: 90)
            badgePath.appendArc(withCenter: NSPoint(x: bx1 + badgeR, y: by2 - badgeR), radius: badgeR, startAngle: 90, endAngle: 180)
            badgePath.close()
            color.setFill()
            badgePath.fill()

            // Badge time label
            let timeStr = timeFmt.string(from: ev.start) as NSString
            let timeFont = NSFont.boldSystemFont(ofSize: fontSize)
            let timeAttrs: [NSAttributedString.Key: Any] = [.font: timeFont, .foregroundColor: NSColor.white]
            let timeSize = timeStr.size(withAttributes: timeAttrs)
            timeStr.draw(at: NSPoint(x: bx1 + (badgeW - timeSize.width) / 2,
                                     y: cy - timeSize.height / 2),
                         withAttributes: timeAttrs)

            // Event title + duration
            let dur = durString(ev)
            let label = dur.isEmpty ? ev.title : "\(ev.title)  \(dur)"
            let txtColor: NSColor = done ? NSColor(hex: "#3a3a3c") : pri
            let font = isFocused ? NSFont.boldSystemFont(ofSize: fontSize) : NSFont.systemFont(ofSize: fontSize)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: txtColor]
            let ns = label as NSString
            let sz = ns.size(withAttributes: attrs)

            let hourComponent = Calendar.current.component(.hour, from: ev.start)
            if hourComponent >= 13 {
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
        let timelineH = axisH + CGFloat(todayEvents.count) * rowH + 10
        let winH = max(230, timelineH + 54) + 4
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

        let root = NSView(frame: contentView!.bounds)
        root.autoresizingMask = [.width, .height]
        root.wantsLayer = true
        root.layer?.backgroundColor = rightBG.cgColor
        contentView = root

        buildUI(root: root, accent: accent, timelineH: timelineH)

        NSSound.playSystemSound("Glass")
    }

    private func buildUI(root: NSView, accent: NSColor, timelineH: CGFloat) {
        let (badgeText, _) = urgency(event)
        let winH = root.bounds.height
        let winW = root.bounds.width
        let leftW: CGFloat = 210

        // Top accent bar
        let bar = NSView(frame: NSRect(x: 0, y: winH - 4, width: winW, height: 4))
        bar.wantsLayer = true; bar.layer?.backgroundColor = accent.cgColor
        bar.autoresizingMask = [.width, .minYMargin]
        root.addSubview(bar)

        // Separator
        let sepV = NSView(frame: NSRect(x: leftW, y: 0, width: 1, height: winH - 4))
        sepV.wantsLayer = true; sepV.layer?.backgroundColor = sep.cgColor
        sepV.autoresizingMask = [.minXMargin, .height]
        root.addSubview(sepV)

        buildLeft(root: root, accent: accent, badgeText: badgeText, leftW: leftW, winH: winH)
        buildRight(root: root, leftW: leftW, winW: winW, winH: winH, timelineH: timelineH, accent: accent)
    }

    private func buildLeft(root: NSView, accent: NSColor, badgeText: String, leftW: CGFloat, winH: CGFloat) {
        let pad: CGFloat = 18
        let left = NSView(frame: NSRect(x: 0, y: 0, width: leftW, height: winH - 4))
        left.wantsLayer = true; left.layer?.backgroundColor = leftBG.cgColor
        left.autoresizingMask = [.height]
        root.addSubview(left)

        // Urgency pill
        let pillH: CGFloat = 20
        let pillAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 9), .foregroundColor: NSColor.white
        ]
        let pillW = (badgeText as NSString).size(withAttributes: pillAttrs).width + 16
        let pill = NSView(frame: NSRect(x: pad, y: winH - 4 - 16 - pillH, width: pillW, height: pillH))
        pill.wantsLayer = true
        pill.layer?.backgroundColor = accent.cgColor
        pill.layer?.cornerRadius = 4
        left.addSubview(pill)

        let pillLabel = NSTextField(labelWithString: badgeText)
        pillLabel.font = NSFont.boldSystemFont(ofSize: 9)
        pillLabel.textColor = .white
        pillLabel.sizeToFit()
        pillLabel.frame.origin = NSPoint(x: 8, y: (pillH - pillLabel.frame.height) / 2)
        pill.addSubview(pillLabel)

        // Event title
        let titleField = NSTextField(wrappingLabelWithString: event.title)
        titleField.font = NSFont.boldSystemFont(ofSize: 16)
        titleField.textColor = pri
        titleField.preferredMaxLayoutWidth = leftW - pad * 2
        titleField.sizeToFit()
        titleField.frame = NSRect(x: pad, y: pill.frame.minY - 10 - titleField.frame.height,
                                  width: leftW - pad * 2, height: titleField.frame.height)
        left.addSubview(titleField)

        // Duration
        let dur = durString(event)
        if !dur.isEmpty {
            let durField = NSTextField(labelWithString: dur)
            durField.font = NSFont.systemFont(ofSize: 12)
            durField.textColor = sec
            durField.sizeToFit()
            durField.frame.origin = NSPoint(x: pad, y: titleField.frame.minY - 4 - durField.frame.height)
            left.addSubview(durField)
        }

        // Dismiss button
        let btn = makeButton(title: "Dismiss", color: accent, target: self, action: #selector(dismiss))
        btn.frame = NSRect(x: leftW - pad - btn.frame.width, y: pad, width: btn.frame.width, height: btn.frame.height)
        left.addSubview(btn)
    }

    private func buildRight(root: NSView, leftW: CGFloat, winW: CGFloat, winH: CGFloat, timelineH: CGFloat, accent: NSColor) {
        let rightW = winW - leftW - 1
        let right = NSView(frame: NSRect(x: leftW + 1, y: 0, width: rightW, height: winH - 4))
        right.autoresizingMask = [.width, .height]
        root.addSubview(right)

        // Date header
        let fmt = DateFormatter(); fmt.dateFormat = "EEEE, MMM d"
        let dateField = NSTextField(labelWithString: fmt.string(from: Date()))
        dateField.font = NSFont.boldSystemFont(ofSize: 11)
        dateField.textColor = sec
        dateField.sizeToFit()
        dateField.frame.origin = NSPoint(x: 12, y: winH - 4 - 9 - dateField.frame.height)
        right.addSubview(dateField)

        // Separator below header
        let hSep = NSView(frame: NSRect(x: 12, y: dateField.frame.minY - 1, width: rightW - 24, height: 1))
        hSep.wantsLayer = true; hSep.layer?.backgroundColor = sep.cgColor
        right.addSubview(hSep)

        // Timeline
        let timeline = TimelineView(frame: NSRect(x: 4, y: hSep.frame.minY - 6 - timelineH,
                                                   width: rightW - 8, height: timelineH))
        timeline.todayEvents = todayEvents
        timeline.focused     = event
        timeline.accent      = accent
        right.addSubview(timeline)
    }

    @objc private func dismiss() { close() }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 || event.keyCode == 36 { close() } // Esc or Return
        else { super.keyDown(with: event) }
    }
}

// MARK: - Helpers

private func makeButton(title: String, color: NSColor, target: AnyObject, action: Selector) -> NSButton {
    let btn = NSButton(title: title, target: target, action: action)
    btn.bezelStyle = .rounded
    btn.wantsLayer = true
    btn.layer?.backgroundColor = color.cgColor
    btn.layer?.cornerRadius = 6
    btn.contentTintColor = .white
    btn.font = NSFont.boldSystemFont(ofSize: 12)
    btn.sizeToFit()
    btn.frame.size = NSSize(width: btn.frame.width + 16, height: 30)
    return btn
}

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
