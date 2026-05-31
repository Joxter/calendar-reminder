import AppKit

// MARK: - Urgency accent colors
private let accentInProgress = NSColor(hex: "#dc2626")  // red
private let accentSoon       = NSColor(hex: "#2563eb")  // blue

// MARK: - Layout constants
//
// Window layout (two columns, side by side):
//   ┌───────────────────────────────────────────────┐
//   │ "Left column"    │ "Timeline column"          │
//   │ <selected event> │  <weekday, current day>    │
//   │                  │                            │
//   │ <next event>     │  <grid with events>        │
//   └───────────────────────────────────────────────┘
//
//   Selected event:
//      - fixed height for:
//        - calendar name (1 line)
//        - event title (2 lines max)
//        - time · duration
//
//   Next event:
//      - fixed height for:
//        - "next" label
//        - event title (2 lines max)
//        - countdown timer
//
//   Grid:
//      - background: vertical gray lines with the hour number at the bottom, full height, below the title (weekday, current day)
//      - vertical red line for the current time (at top)
//      - rows with events:
//         - fixed height
//         - text has a white background, so the red line and grid lines don't show under the text (time and event names)
//         - events are clickable; user selects an event by clicking, a second click unselects
//         - only the selected event is bold
//
//
//    Important details:
//      - Window height = window_padding + max_possible_height_of_selected_event + GAP + max_possible_height_of_next_event + window_padding
//      - Window height is constant, even for the "no events" case
//      - Grid is full height (except the title)
//      - calculate the max number of events based on window height, row height, and the gaps between them
//      - if we have more events than the max: show at most 2 previous events and add ("X more" to indicate there are more); do the same for future events (show as many as possible and add "X more")
//      - timeline should show at least the 8:00 - 20:00 period; even if we have one event in the middle, extend the timeline (according to start and end time), but show nothing after 3:00 past midnight (we can add a fade)
//      - some fixed width for the left and timeline columns
//      - we should have extra variables to adjust window padding for the left and right columns separately
//      - left column changes color based on the timer (blue by default, red if less than 2 minutes)
//
// Timeline title placement:
//   Morning (hour < 13): title right of time label, tail-truncated to right edge.
//   Afternoon (hour ≥ 13): title sits left of the start marker with a small gap,
//                           capped at maxTimelineTitleW, tail-truncated.

private let axisH: CGFloat  = 20
private let badgeH: CGFloat = 16
private let lPad: CGFloat   = 10
private let rPad: CGFloat   = 10

// Right-column font size — single knob that scales all timeline text.
private let timelineFontSize: CGFloat = 13
private var rowH: CGFloat { timelineFontSize + 10 }   // 23px at default font size

// Left column spacing
private let gapNextToTitle: CGFloat  =  0   // "NEXT" label to event title
private let gapTitleToTimer: CGFloat = -1   // event title to countdown (slight visual tuck)

// L-shape style
private let shapeStrokeW: CGFloat  = 2   // stroke thickness
private let shapeCornerR: CGFloat  = 4   // corner radius (0 = sharp, max = badgeH/2 = 8)

// Window padding — separate knobs for the two columns.
private let leftColPad:  CGFloat = 16   // inset inside the left column
private let rightColPad: CGFloat = 4    // inset inside the right (timeline) column
private let winVPad:     CGFloat = 16   // top & bottom padding of window content (left column)
private let panelGap:    CGFloat = 16   // gap between the selected-event and next-event slots
private let dateHeaderH:   CGFloat = 22  // right-column date header height
private let dateHeaderTop: CGFloat = 9   // top inset above the date header
private let dateHeaderGap: CGFloat = 6   // gap between date header and timeline

private let maxTimelineTitleW: CGFloat = 240
private let maxPastVisible: Int = 2      // past events shown before collapsing into "+N more"

// Left-column accent: blue by default, red when next event is < urgentThreshold away.
private let accentDefault = accentSoon         // blue  (#2563eb)
private let accentUrgent  = accentInProgress   // red   (#dc2626)
private let accentNone    = NSColor(hex: "#475569")  // neutral gray (no next event)
private let urgentThreshold: TimeInterval = 120

// Left-panel title fields — 2 lines max.
// NSTextField.maximumNumberOfLines does NOT cap Auto Layout intrinsic content size in
// AppKit, so an explicit heightAnchor constraint is required to prevent expansion.
private let leftPanelTitleFontSz: CGFloat = 15
private let leftPanelMaxTitleLines: Int   = 2
private var leftPanelTitleMaxH: CGFloat {
    let f = NSFont.boldSystemFont(ofSize: leftPanelTitleFontSz)
    return ceil(f.ascender - f.descender + f.leading) * CGFloat(leftPanelMaxTitleLines) + 4
}

// Heights derived from font metrics for left-column window sizing.
private var timerLineH: CGFloat {
    let f = NSFont.monospacedDigitSystemFont(ofSize: 52, weight: .black)
    return ceil(f.ascender - f.descender + f.leading)
}
private var nextLblLineH: CGFloat { ceil(NSFont.boldSystemFont(ofSize: 9).boundingRectForFont.height) }
private var infoLineH:    CGFloat { ceil(NSFont.systemFont(ofSize: 11).boundingRectForFont.height) }
private var calLblLineH:  CGFloat { ceil(NSFont.systemFont(ofSize: 10, weight: .medium).boundingRectForFont.height) }

// Selected-event slot (top): calLabel + calGap + title + infoGap + info
private var selectedSlotH: CGFloat { calLblLineH + 4 + leftPanelTitleMaxH + 6 + infoLineH }
// Next-event slot (bottom): nextLabel + title + 1pt tuck + timer
private var nextSlotH:     CGFloat { nextLblLineH + leftPanelTitleMaxH + 1 + timerLineH }
// Constant window content height: both slots always reserved, regardless of events.
private var winContentH:   CGFloat { winVPad + selectedSlotH + panelGap + nextSlotH + winVPad }
// Rows that fit in the right column's grid given the fixed window height.
private var maxTimelineRows: Int {
    let gridH = winContentH - dateHeaderTop - dateHeaderH - dateHeaderGap - rightColPad - 2 * axisH
    return max(1, Int(gridH / rowH))
}

/// Formats a duration in minutes as "Xh Ym", capped at 23:59 (1439 min).
private func durString(minutes rawMin: Int) -> String {
    guard rawMin > 0 else { return "" }
    let m = min(rawMin, 23 * 60 + 59)
    let h = m / 60, rem = m % 60
    return h > 0 ? (rem > 0 ? "\(h)h \(rem)m" : "\(h)h") : "\(rem)m"
}

/// Left-column accent: gray when no next event, red when imminent, blue otherwise.
private func accentColor(for next: CalEvent?) -> NSColor {
    guard let next else { return accentNone }
    return next.startsInSeconds <= urgentThreshold ? accentUrgent : accentDefault
}

/// Countdown string: "H:MM" when ≥ 1h away, "MM:SS" otherwise, "NOW" once started.
private func countdownText(_ rawSecs: TimeInterval) -> String {
    let secs = max(0, rawSecs)
    guard secs > 0 else { return "NOW" }
    let totalMin = Int(secs) / 60
    if totalMin >= 60 {
        return String(format: "%d:%02d", totalMin / 60, totalMin % 60)
    }
    return String(format: "%02d:%02d", totalMin, Int(secs) % 60)
}


// MARK: - Timeline View

final class TimelineView: NSView {
    var todayEvents: [CalEvent] = []   // visible events only (already trimmed)
    var hiddenPast: Int = 0            // collapsed past events ("+N more" row at top)
    var hiddenFuture: Int = 0          // collapsed future events ("+N more" row at bottom)
    var focused: CalEvent?
    var accent: NSColor = .systemBlue
    var onEventSelected: ((CalEvent) -> Void)?

    // y=0 at top, increasing downward — matches Python/tkinter exactly
    override var isFlipped: Bool { true }

    // Event rows are pushed down by one when a "+N more" past row occupies row 0.
    private var rowOffset: Int { hiddenPast > 0 ? 1 : 0 }

    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        let row = Int((loc.y - axisH) / rowH) - rowOffset
        guard row >= 0, row < todayEvents.count else { return }
        onEventSelected?(todayEvents[row])
    }

    override func resetCursorRects() {
        for i in todayEvents.indices {
            let y = axisH + CGFloat(i + rowOffset) * rowH
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
        var re = cal.date(bySettingHour: 20, minute: 0, second: 0, of: now)!
        if let first = todayEvents.first {
            rs = min(rs, cal.date(bySetting: .minute, value: 0, of: first.start)!)
        }
        if let last = todayEvents.last {
            re = max(re, cal.date(bySetting: .minute, value: 0, of: last.end)!)
        }
        // Never extend past 3:00 the morning after the displayed day.
        let cap3am = cal.date(byAdding: .hour, value: 27, to: cal.startOfDay(for: now))!
        re = min(re, cap3am)

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
            let cy = axisH + CGFloat(i + rowOffset) * rowH + rowH / 2
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

        // "+N more" collapse rows: past at the top (row 0), future at the bottom.
        let moreAttrs: [NSAttributedString.Key: Any] = [
            .font:            NSFont.systemFont(ofSize: timelineFontSize - 1),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]
        func drawMore(_ text: String, atRow row: Int) {
            let cy  = axisH + CGFloat(row) * rowH + rowH / 2
            let str = text as NSString
            let sz  = str.size(withAttributes: moreAttrs)
            str.draw(at: NSPoint(x: lPad, y: cy - sz.height / 2), withAttributes: moreAttrs)
        }
        if hiddenPast > 0 {
            drawMore("+\(hiddenPast) earlier", atRow: 0)
        }
        if hiddenFuture > 0 {
            drawMore("+\(hiddenFuture) more", atRow: rowOffset + todayEvents.count)
        }
    }
}

// MARK: - Reminder Window

final class ReminderWindow: NSWindow {
    private let event: CalEvent?          // triggering event (nil = opened without a reminder)
    private let nextEvent: CalEvent?      // event shown in the bottom slot / drives the countdown + color
    private let todayEvents: [CalEvent]   // visible timeline events (already trimmed)
    private let hiddenPast: Int
    private let hiddenFuture: Int

    private var countdownField: NSTextField?
    private var colonVisible   = true
    private var tickTimer: Timer?

    private var leftColumn: NSView?
    private var timelineView: TimelineView?
    private var selectedSlot: NSView?     // top slot — filled on timeline click
    private var nextSlotView: NSView?     // bottom slot — next event
    private var selectedEvent: CalEvent?

    init(event: CalEvent?, todayEvents allEvents: [CalEvent]) {
        self.event = event
        let now = Config.now

        // Split into past (ended) and current/future, then trim each side with a collapse row.
        let past   = allEvents.filter { $0.end <= now }
        let future = allEvents.filter { $0.end >  now }

        let shownPast = Array(past.suffix(maxPastVisible))
        let hp        = past.count - shownPast.count

        let budget = max(0, maxTimelineRows - (hp > 0 ? 1 : 0) - shownPast.count)
        var shownFuture = future
        var hf = 0
        if future.count > budget {
            shownFuture = Array(future.prefix(max(0, budget - 1)))  // reserve a row for "+N more"
            hf = future.count - shownFuture.count
        }

        self.todayEvents  = shownPast + shownFuture
        self.hiddenPast   = hp
        self.hiddenFuture = hf
        self.nextEvent    = event ?? future.first

        let accent = accentColor(for: nextEvent)
        let winH   = winContentH
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
        if event != nil, Config.soundEnabled { NSSound.playSystemSound("Glass") }
        if nextEvent != nil { startTickTimer() }
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

        self.leftColumn = left

        buildLeftSlots(in: left)
        buildRight(in: right, accent: accent)
    }

    // Two fixed-height slots that are always reserved: selected event (top), next event (bottom).
    private func buildLeftSlots(in left: NSView) {
        let selected = NSView()
        selected.translatesAutoresizingMaskIntoConstraints = false
        left.addSubview(selected)

        let next = NSView()
        next.translatesAutoresizingMaskIntoConstraints = false
        left.addSubview(next)

        NSLayoutConstraint.activate([
            selected.topAnchor.constraint(equalTo: left.topAnchor, constant: winVPad),
            selected.leadingAnchor.constraint(equalTo: left.leadingAnchor),
            selected.trailingAnchor.constraint(equalTo: left.trailingAnchor),
            selected.heightAnchor.constraint(equalToConstant: selectedSlotH),

            next.bottomAnchor.constraint(equalTo: left.bottomAnchor, constant: -winVPad),
            next.leadingAnchor.constraint(equalTo: left.leadingAnchor),
            next.trailingAnchor.constraint(equalTo: left.trailingAnchor),
            next.heightAnchor.constraint(equalToConstant: nextSlotH),
        ])

        self.selectedSlot = selected
        self.nextSlotView = next

        if let nextEvent { buildNextContent(in: next, event: nextEvent) }
        else             { buildAllClear(in: next) }
    }

    // Bottom slot: "NEXT" label, event title (2 lines), big countdown timer.
    private func buildNextContent(in view: NSView, event: CalEvent) {
        let white = NSColor.white

        let nextLbl = NSTextField(labelWithString: "NEXT")
        nextLbl.translatesAutoresizingMaskIntoConstraints = false
        nextLbl.font      = NSFont.boldSystemFont(ofSize: 9)
        nextLbl.textColor = white.withAlphaComponent(0.9)
        view.addSubview(nextLbl)

        // The explicit heightAnchor is required: maximumNumberOfLines alone does
        // not cap the Auto Layout intrinsic content size in AppKit.
        let titleField = NSTextField(wrappingLabelWithString: event.title)
        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.font                    = NSFont.boldSystemFont(ofSize: leftPanelTitleFontSz)
        titleField.textColor               = white.withAlphaComponent(0.9)
        titleField.preferredMaxLayoutWidth = 210 - leftColPad * 2
        titleField.maximumNumberOfLines    = leftPanelMaxTitleLines
        (titleField.cell as? NSTextFieldCell)?.truncatesLastVisibleLine = true
        titleField.heightAnchor.constraint(lessThanOrEqualToConstant: leftPanelTitleMaxH).isActive = true
        view.addSubview(titleField)

        let timerField = NSTextField(labelWithString: countdownText(event.startsInSeconds))
        timerField.translatesAutoresizingMaskIntoConstraints = false
        timerField.font      = NSFont.monospacedDigitSystemFont(ofSize: 52, weight: .black)
        timerField.textColor = white
        view.addSubview(timerField)
        self.countdownField = timerField

        NSLayoutConstraint.activate([
            nextLbl.topAnchor.constraint(equalTo: view.topAnchor),
            nextLbl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: leftColPad),

            titleField.topAnchor.constraint(equalTo: nextLbl.bottomAnchor, constant: gapNextToTitle),
            titleField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: leftColPad),
            titleField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -leftColPad),

            timerField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: leftColPad - 4),
            timerField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -leftColPad),
            timerField.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    // Fallback for the bottom slot when there is no upcoming event.
    private func buildAllClear(in view: NSView) {
        let heading = NSTextField(labelWithString: "All clear")
        heading.translatesAutoresizingMaskIntoConstraints = false
        heading.font      = NSFont.boldSystemFont(ofSize: 15)
        heading.textColor = NSColor.white
        view.addSubview(heading)

        NSLayoutConstraint.activate([
            heading.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: leftColPad),
            heading.bottomAnchor.constraint(equalTo: view.bottomAnchor),
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
        timeline.hiddenPast   = hiddenPast
        timeline.hiddenFuture = hiddenFuture
        timeline.focused      = nil
        timeline.accent       = accent
        timeline.onEventSelected = { [weak self] ev in self?.handleTimelineEventSelected(ev) }
        right.addSubview(timeline)
        self.timelineView = timeline

        NSLayoutConstraint.activate([
            dateField.leadingAnchor.constraint(equalTo: right.leadingAnchor, constant: rightColPad + 8),
            dateField.topAnchor.constraint(equalTo: right.topAnchor, constant: dateHeaderTop),

            timeline.leadingAnchor.constraint(equalTo: right.leadingAnchor, constant: rightColPad),
            timeline.trailingAnchor.constraint(equalTo: right.trailingAnchor, constant: -rightColPad),
            timeline.topAnchor.constraint(equalTo: dateField.bottomAnchor, constant: dateHeaderGap),
            timeline.bottomAnchor.constraint(equalTo: right.bottomAnchor, constant: -rightColPad),
        ])
    }

    // MARK: - Timeline event selection

    private func handleTimelineEventSelected(_ ev: CalEvent) {
        guard let slot = selectedSlot else { return }

        // Always clear the slot first; toggle off if re-clicking the current selection.
        slot.subviews.forEach { $0.removeFromSuperview() }
        if selectedEvent == ev {
            selectedEvent = nil
            timelineView?.focused = nil
            timelineView?.needsDisplay = true
            return
        }

        selectedEvent = ev
        timelineView?.focused = ev
        timelineView?.needsDisplay = true
        buildSelectedContent(in: slot, event: ev)
    }

    // Top slot: calendar name, event title (2 lines), time · duration. Top-aligned.
    private func buildSelectedContent(in view: NSView, event: CalEvent) {
        let white = NSColor.white

        let timeFmt = DateFormatter(); timeFmt.dateFormat = "HH:mm"
        let timeStr = "\(timeFmt.string(from: event.start)) – \(timeFmt.string(from: event.end))"
        let dur     = durString(minutes: Int(event.duration / 60))

        var topAnchor: NSLayoutYAxisAnchor = view.topAnchor
        var topConstant: CGFloat = 0

        if let name = event.calendarName {
            let calLabel = NSTextField(labelWithString: name)
            calLabel.translatesAutoresizingMaskIntoConstraints = false
            calLabel.font          = NSFont.systemFont(ofSize: 10, weight: .medium)
            calLabel.textColor     = white.withAlphaComponent(0.55)
            calLabel.lineBreakMode = .byTruncatingTail
            view.addSubview(calLabel)
            NSLayoutConstraint.activate([
                calLabel.topAnchor.constraint(equalTo: view.topAnchor),
                calLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: leftColPad),
                calLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -leftColPad),
            ])
            topAnchor = calLabel.bottomAnchor
            topConstant = 4
        }

        let titleField = NSTextField(wrappingLabelWithString: event.title)
        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.font                    = NSFont.boldSystemFont(ofSize: leftPanelTitleFontSz)
        titleField.textColor               = white
        titleField.preferredMaxLayoutWidth = 210 - leftColPad * 2
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
            titleField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: leftColPad),
            titleField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -leftColPad),

            infoField.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 6),
            infoField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: leftColPad),
            infoField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -leftColPad),
        ])
    }

    private func startTickTimer() {
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        guard let nextEvent = nextEvent, let field = countdownField else { return }
        colonVisible.toggle()

        // Recolor the left column live: blue by default, red when imminent.
        leftColumn?.layer?.backgroundColor = accentColor(for: nextEvent).cgColor

        let text = countdownText(nextEvent.startsInSeconds)
        let white = NSColor.white
        let font  = NSFont.monospacedDigitSystemFont(ofSize: 52, weight: .black)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: white]
        let attributed = NSMutableAttributedString(string: text, attributes: attrs)
        if let colonRange = text.range(of: ":") {
            let nsRange = NSRange(colonRange, in: text)
            attributed.addAttribute(.foregroundColor,
                                    value: white.withAlphaComponent(colonVisible ? 1 : 0),
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
