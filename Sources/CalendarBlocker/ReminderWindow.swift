import AppKit

// MARK: - Urgency accent colors
private let accentInProgress = NSColor(hex: "#dc2626")  // red
private let accentImminent   = NSColor(hex: "#7c3aed")  // purple
private let accentSoon       = NSColor(hex: "#2563eb")  // blue

// MARK: - Layout constants
//
// Window layout (two columns, side by side):
//   ┌──────────────────────────────────────────────────┐
//   │ Left (210px wide)   │ Right (fills remainder)    │
//   │ accent-color panel  │ white panel                │
//   │                     │  date header  (9pt top pad)│
//   │  [NEXT]  ← or →     │  TimelineView (fills rest) │
//   │  event title        │   axisH (20) top strip     │
//   │  (max 2 lines)      │   N × rowH event rows      │
//   │  countdown timer    │   <empty space + gridlines>│
//   │  ─── selected ───   │   axisH (20) hour labels   │
//   │  calendar name      │                            │
//   │  event title        │                            │
//   │  time · duration    │                            │
//   └──────────────────────────────────────────────────┘
//
// Window height = min(maxWinH, max(activeMinH, 2×axisH + rows×rowH + winOverhead))
//   winOverhead  = topInset(9) + dateHeaderH(~19) + headerGap(6) + bottomInset(4) = 38
//   TimelineView fills the right panel via bottomAnchor, so gridlines and the hour-label
//   strip always span the full right-panel height regardless of event count.
//   maxTimelineRows = ⌊(maxWinH − winOverhead − 2×axisH) / rowH⌋
//                   = ⌊(500 − 38 − 40) / 23⌋ = 18
//
// Left panel (no NEXT event):  placeholder "All clear".  activeMinH = minWinH (230).
//
// Left panel (NEXT event exists):  two stacks coexist when user selects a timeline row.
//   Detail panel (top-anchored):
//     topPad(16) + calLabel(calLblLineH) + calGap(4) + title(titleMaxH)
//     + infoGap(6) + info(infoLineH) + botPad(16)
//   NEXT stack (bottom-pinned, from window bottom to "NEXT" label top):
//     botPad(16) + timer(timerLineH) + 1pt + title(titleMaxH) + nextLabel(nextLblLineH)
//   Gap between panels: panelGap (16)
//   activeMinH = minWinHWithEvent = detailPanelH + panelGap + nextStackH  (computed)
//
// Timeline title placement:
//   Morning (hour < 13): title right of time label, tail-truncated to right edge.
//   Afternoon (hour ≥ 13): title left of L-shape start, right-edge at x1−6,
//                           capped at maxTimelineTitleW (160), tail-truncated.

private let axisH: CGFloat  = 20
private let badgeH: CGFloat = 16
private let lPad: CGFloat   = 10
private let rPad: CGFloat   = 10

// Right-column font size — single knob that scales all timeline text.
private let timelineFontSize: CGFloat = 13
private var rowH: CGFloat { timelineFontSize + 10 }   // 23px at default font size

// Left panel spacing
private let gapNextToTitle: CGFloat  =  0   // "NEXT" label to event title
private let gapTitleToTimer: CGFloat = -1   // event title to countdown (slight visual tuck)

// L-shape style
private let shapeStrokeW: CGFloat  = 2   // stroke thickness
private let shapeCornerR: CGFloat  = 4   // corner radius (0 = sharp, max = badgeH/2 = 8)

private let maxWinH:    CGFloat = 400
private let minWinH:    CGFloat = 230   // no NEXT event (placeholder only)
private let winOverhead: CGFloat = 58   // space from window top/bottom to timeline view edges
private let panelGap:   CGFloat = 16   // breathing room between detail and NEXT panels
private let maxTimelineTitleW: CGFloat = 240

private var maxTimelineRows: Int { Int((maxWinH - winOverhead - 2 * axisH) / rowH) }

// Left-panel title fields — 2 lines max.
// NSTextField.maximumNumberOfLines does NOT cap Auto Layout intrinsic content size in
// AppKit, so an explicit heightAnchor constraint is required to prevent expansion.
private let leftPanelTitleFontSz: CGFloat = 15
private let leftPanelMaxTitleLines: Int   = 2
private var leftPanelTitleMaxH: CGFloat {
    let f = NSFont.boldSystemFont(ofSize: leftPanelTitleFontSz)
    return ceil(f.ascender - f.descender + f.leading) * CGFloat(leftPanelMaxTitleLines) + 4
}

// Heights derived from font metrics for left-panel window sizing.
private var timerLineH: CGFloat {
    let f = NSFont.monospacedDigitSystemFont(ofSize: 52, weight: .black)
    return ceil(f.ascender - f.descender + f.leading)
}
private var nextLblLineH: CGFloat { ceil(NSFont.boldSystemFont(ofSize: 9).boundingRectForFont.height) }
private var infoLineH:    CGFloat { ceil(NSFont.systemFont(ofSize: 11).boundingRectForFont.height) }
private var calLblLineH:  CGFloat { ceil(NSFont.systemFont(ofSize: 10, weight: .medium).boundingRectForFont.height) }

// detail panel: topPad + calLabel + calGap + title + infoGap + info + botPad
private var detailPanelH: CGFloat { 16 + calLblLineH + 4 + leftPanelTitleMaxH + 6 + infoLineH + 16 }
// NEXT stack: botPad + timer + 1pt tuck + title + nextLabel
private var nextStackH:   CGFloat { 16 + timerLineH + 1 + leftPanelTitleMaxH + nextLblLineH }
// min window height when NEXT event is present (two panels must fit without overlap)
private var minWinHWithEvent: CGFloat { detailPanelH + panelGap + nextStackH }

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

/// Formats a duration in minutes as "Xh Ym", capped at 23:59 (1439 min).
private func durString(minutes rawMin: Int) -> String {
    guard rawMin > 0 else { return "" }
    let m = min(rawMin, 23 * 60 + 59)
    let h = m / 60, rem = m % 60
    return h > 0 ? (rem > 0 ? "\(h)h \(rem)m" : "\(h)h") : "\(rem)m"
}


// MARK: - Timeline View

final class TimelineView: NSView {
    var todayEvents: [CalEvent] = []
    var hiddenCount: Int = 0
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

        // Hour gridlines + axis labels (labels at bottom)
        var cur = rs
        let lblAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: timelineFontSize - 2, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let bottomY = bounds.height - axisH - 18  // top of bottom label area; fills full height
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

        // Precompute per-event layout so we can use it across passes.
        // titleRect width = actual rendered text width (capped at maxW), so white backgrounds
        // don't bleed into the now-line or beyond available space.
        // Morning titles: left-aligned after the time label, capped by right edge.
        // Afternoon titles: right-aligned to the event start (x1-6), capped at maxTimelineTitleW.
        struct EvLayout {
            let cy: CGFloat, x1: CGFloat, x2: CGFloat
            let color: NSColor, alpha: CGFloat
            let timeStr: NSString, timeAttrs: [NSAttributedString.Key: Any]
            let timeSz: NSSize, timeOrigin: NSPoint
            let titleStr: NSString, titleAttrs: [NSAttributedString.Key: Any]
            let titleRect: NSRect
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

            let txtColor    = done ? NSColor.tertiaryLabelColor : NSColor.labelColor
            let font        = isFocused ? NSFont.boldSystemFont(ofSize: timelineFontSize) : NSFont.systemFont(ofSize: timelineFontSize)
            let isAfternoon = Calendar.current.component(.hour, from: ev.start) >= 13
            let afterTimeX  = x1 + shapeStrokeW / 2 + 4 + timeSz.width + 6

            let truncPara = NSMutableParagraphStyle()
            truncPara.lineBreakMode = .byTruncatingTail
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: font, .foregroundColor: txtColor, .paragraphStyle: truncPara,
            ]
            let titleStr = ev.title as NSString
            let naturalW = titleStr.size(withAttributes: titleAttrs).width
            let titleH   = titleStr.size(withAttributes: titleAttrs).height

            let titleRect: NSRect
            if isAfternoon {
                // Cap at maxTimelineTitleW; right-edge sits at x1−6 (just before the L-shape).
                let maxW  = min(maxTimelineTitleW, max(0, x1 - 6 - lPad))
                let drawW = min(naturalW, maxW)
                titleRect = NSRect(x: x1 - 6 - drawW, y: cy - titleH / 2, width: drawW, height: titleH)
            } else {
                let maxW  = max(0, w - rPad - afterTimeX)
                let drawW = min(naturalW, maxW)
                titleRect = NSRect(x: afterTimeX, y: cy - titleH / 2, width: drawW, height: titleH)
            }

            layouts.append(EvLayout(cy: cy, x1: x1, x2: x2, color: color, alpha: alpha,
                                    timeStr: timeStr, timeAttrs: timeAttrs,
                                    timeSz: timeSz, timeOrigin: timeOrigin,
                                    titleStr: titleStr, titleAttrs: titleAttrs,
                                    titleRect: titleRect))
        }

        // Pass 1: white backgrounds behind text (sized to actual rendered width)
        NSColor.white.setFill()
        for l in layouts {
            NSBezierPath(rect: NSRect(origin: l.timeOrigin, size: l.timeSz).insetBy(dx: -2, dy: 0)).fill()
            NSBezierPath(rect: l.titleRect.insetBy(dx: -2, dy: 0)).fill()
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
            l.timeStr.draw(at: l.timeOrigin, withAttributes: l.timeAttrs)
            l.titleStr.draw(in: l.titleRect, withAttributes: l.titleAttrs)
        }

        // "+N more" footer row when events were trimmed
        if hiddenCount > 0 {
            let footerCy = axisH + CGFloat(todayEvents.count) * rowH + rowH / 2
            let moreStr  = "+\(hiddenCount) more" as NSString
            let moreAttrs: [NSAttributedString.Key: Any] = [
                .font:            NSFont.systemFont(ofSize: timelineFontSize - 1),
                .foregroundColor: NSColor.tertiaryLabelColor,
            ]
            let moreSz = moreStr.size(withAttributes: moreAttrs)
            moreStr.draw(at: NSPoint(x: lPad, y: footerCy - moreSz.height / 2), withAttributes: moreAttrs)
        }
    }
}

// MARK: - Reminder Window

final class ReminderWindow: NSWindow {
    private let event: CalEvent?
    private let todayEvents: [CalEvent]
    private let hiddenEventCount: Int

    private var countdownField: NSTextField?
    private var countdownColor = NSColor.white
    private var colonVisible   = true
    private var tickTimer: Timer?

    private var leftColumn: NSView?
    private var timelineView: TimelineView?
    private var detailContainer: NSView?
    private var selectedEvent: CalEvent?
    private var accentColor: NSColor = NSColor(hex: "#475569")

    init(event: CalEvent?, todayEvents allEvents: [CalEvent]) {
        self.event = event
        // Cap visible rows; if overflow exists, replace the last visible slot with the "+N more" footer.
        let cap = maxTimelineRows
        if allEvents.count > cap {
            self.todayEvents      = Array(allEvents.prefix(cap - 1))
            self.hiddenEventCount = allEvents.count - (cap - 1)
        } else {
            self.todayEvents      = allEvents
            self.hiddenEventCount = 0
        }
        let visibleRows = todayEvents.count + (hiddenEventCount > 0 ? 1 : 0)

        let accent: NSColor = event.map { urgency($0).1 } ?? NSColor(hex: "#475569")
        let activeMinH = event != nil ? minWinHWithEvent : minWinH
        let timelineH  = axisH + CGFloat(max(visibleRows, 1)) * rowH + axisH
        let winH       = min(maxWinH, max(activeMinH, timelineH + winOverhead - 4) + 4)
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

        buildUI(accent: accent)
        if event != nil {
            if Config.soundEnabled { NSSound.playSystemSound("Glass") }
            startTickTimer()
        }
    }

    // MARK: - UI

    private func buildUI(accent: NSColor) {
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
        buildRight(in: right, accent: accent)
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

        // Event title — capped at leftPanelMaxTitleLines.
        // The explicit heightAnchor constraint is required: maximumNumberOfLines alone does
        // not limit the Auto Layout intrinsic content size in AppKit.
        let titleField = NSTextField(wrappingLabelWithString: event.title)
        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.font                    = NSFont.boldSystemFont(ofSize: leftPanelTitleFontSz)
        titleField.textColor               = white.withAlphaComponent(0.9)
        titleField.preferredMaxLayoutWidth = 210 - pad * 2
        titleField.maximumNumberOfLines    = leftPanelMaxTitleLines
        (titleField.cell as? NSTextFieldCell)?.truncatesLastVisibleLine = true
        titleField.heightAnchor.constraint(lessThanOrEqualToConstant: leftPanelTitleMaxH).isActive = true
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

    private func buildRight(in right: NSView, accent: NSColor) {
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
        timeline.todayEvents  = todayEvents
        timeline.hiddenCount  = hiddenEventCount
        timeline.focused      = nil
        timeline.accent       = accent
        timeline.onEventSelected = { [weak self] ev in self?.handleTimelineEventSelected(ev) }
        right.addSubview(timeline)
        self.timelineView = timeline

        NSLayoutConstraint.activate([
            dateField.leadingAnchor.constraint(equalTo: right.leadingAnchor, constant: 12),
            dateField.topAnchor.constraint(equalTo: right.topAnchor, constant: 9),

            timeline.leadingAnchor.constraint(equalTo: right.leadingAnchor, constant: 4),
            timeline.trailingAnchor.constraint(equalTo: right.trailingAnchor, constant: -4),
            timeline.topAnchor.constraint(equalTo: dateField.bottomAnchor, constant: 6),
            timeline.bottomAnchor.constraint(equalTo: right.bottomAnchor, constant: -4),
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

        let dur = durString(minutes: Int(event.duration / 60))

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
        titleField.font                    = NSFont.boldSystemFont(ofSize: leftPanelTitleFontSz)
        titleField.textColor               = white
        titleField.preferredMaxLayoutWidth = 210 - pad * 2
        titleField.maximumNumberOfLines    = leftPanelMaxTitleLines
        (titleField.cell as? NSTextFieldCell)?.truncatesLastVisibleLine = true
        titleField.heightAnchor.constraint(lessThanOrEqualToConstant: leftPanelTitleMaxH).isActive = true
        view.addSubview(titleField)

        let infoStr = dur.isEmpty ? timeStr : "\(timeStr)  ·  \(dur)"
        let infoField = NSTextField(labelWithString: infoStr)
        infoField.translatesAutoresizingMaskIntoConstraints = false
        infoField.font          = NSFont.systemFont(ofSize: 11)
        infoField.textColor     = white.withAlphaComponent(0.7)
        infoField.lineBreakMode = .byTruncatingTail
        view.addSubview(infoField)

        NSLayoutConstraint.activate([
            titleField.topAnchor.constraint(equalTo: topAnchor, constant: topConstant),
            titleField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: pad),
            titleField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -pad),

            infoField.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 6),
            infoField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: pad),
            infoField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -pad),

            view.bottomAnchor.constraint(equalTo: infoField.bottomAnchor, constant: pad),
        ])
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
