import AppKit

// MARK: - Urgency accent colors
private let accentInProgress = NSColor(hex: "#dc2626")  // red
private let accentSoon       = NSColor(hex: "#2563eb")  // blue
private let accentNone       = NSColor(hex: "#475569")  // neutral gray (no next event)

// MARK: - Layout constants (mirror web/src/layout.ts)
//
// Window = two columns side by side:
//   ┌───────────────────────────────────────────────┐
//   │ left column      │ right column               │
//   │ <selected event> │  <weekday, day>            │
//   │                  │                            │
//   │ <next event>     │  <timeline OR fallback>    │
//   └───────────────────────────────────────────────┘
//
// Both columns are sized from the events, not fixed:
//   - Width grows with the day's time span (pxPerHour); window width is derived.
//   - Height grows to fit all events (minimum = 7 rows). The left column has a
//     constant minimum height (both slots always reserved); the window takes the
//     taller of the two.
//   - When the timeline is impractical (too many events, or events reaching
//     outside the 8–20h band) the right column switches to a plain scrolling list.

private let leftW: CGFloat = 210

// Left column padding (each side; web leftColPad{T,R,B,L} = 16).
private let leftColPad: CGFloat = 16
private let winVPad:    CGFloat = 16   // left-column top & bottom inset
private let panelGap:   CGFloat = 16   // gap between the selected and next slots

// Right column padding (web rightColPad T/R/B/L = 9/4/4/4).
private let rightColPadT: CGFloat = 9
private let rightColPadR: CGFloat = 4
private let rightColPadB: CGFloat = 4
private let rightColPadL: CGFloat = 4

private let dateHeaderH:      CGFloat = 22
private let dateHeaderGap:    CGFloat = 6   // gap between date header and timeline
private let dateHeaderIndent: CGFloat = 8   // extra left indent of the date text

// Timeline scale.
private let pxPerHour:    CGFloat = 45
private let pxPerMin:     CGFloat = 45.0 / 60.0
private let defaultHourRange = (start: 9, end: 18)   // minimum visible range
private let timelinePadL: CGFloat = 10
private let timelinePadR: CGFloat = 10
private let snapToWholeHours = true

// Timeline height components (sum to the timeline height).
private let nowLabelH:     CGFloat = 20
private let firstEventPad: CGFloat = 8
private let eventsGap:     CGFloat = 4
private let badgeH:        CGFloat = 16
private let rowH:          CGFloat = 16 + 4   // badgeH + eventsGap = 20
private let lastEventPad:  CGFloat = 8
private let hoursH:        CGFloat = 12 + 19  // 31

// Right-column font size — single knob that scales all timeline text.
private let timelineFontSize:   CGFloat = 13
private let maxTimelineTitleW:   CGFloat = 150
private let titleLeftThresholdHour = 13   // events at/after this hour get the title left of the marker

// L-shape style.
private let shapeStrokeW: CGFloat = 2   // stroke thickness
private let shapeCornerR: CGFloat = 4   // corner radius (0 = sharp, max = badgeH/2 = 8)

// Auto-fallback thresholds: the timeline gets impractical when events span too
// wide a day or there are too many of them — switch to the plain list instead.
private let fallbackEarliestHour = 8     // any event starting before this hour
private let fallbackLatestHour   = 20    // any event ending after this hour
private let fallbackMaxEvents    = 10    // more than this many events
private let fallbackListW: CGFloat = 300

// Left-column accent: blue by default, red when next event is < urgentThreshold away.
private let accentDefault = accentSoon         // blue  (#2563eb)
private let accentUrgent  = accentInProgress   // red   (#dc2626)
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

// Heights derived from font metrics for left-column window sizing. These are the
// ground truth the web approximates with `lineHeight(size) = ceil(size * 1.21)`.
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
// Constant minimum window content height: both slots always reserved, regardless of events.
private var winContentH:   CGFloat { winVPad + selectedSlotH + panelGap + nextSlotH + winVPad }

// MARK: - Timeline sizing (mirror layout.ts)

/// Total timeline height for `count` events.
private func timeLineHeight(_ count: Int) -> CGFloat {
    nowLabelH + firstEventPad + CGFloat(count) * rowH + lastEventPad + hoursH
}
private var timelineMinHeight: CGFloat { timeLineHeight(7) }

/// Window width derived from the right-column content width.
private func windowWidth(_ contentW: CGFloat) -> CGFloat {
    leftW + rightColPadL + rightColPadR + contentW
}

private struct TimelineLayout {
    let rs: Date          // range start (left edge time)
    let re: Date          // range end (right edge time)
    let width: CGFloat    // timeline view width
    let height: CGFloat   // timeline view height
}

/// Visible time range: at least the default band, extended to the events, snapped
/// to whole hours, and capped at 03:00 the morning after the displayed day.
private func timeMap(_ events: [CalEvent], now: Date) -> (rs: Date, re: Date) {
    let cal = Calendar.current
    var rs = cal.date(bySettingHour: defaultHourRange.start, minute: 0, second: 0, of: now)!
    var re = cal.date(bySettingHour: defaultHourRange.end,   minute: 0, second: 0, of: now)!

    if let first = events.first, let last = events.last {
        rs = min(rs, first.start)
        re = max(re, last.end)
    }

    if snapToWholeHours {
        let dayStart = cal.startOfDay(for: now)
        let rsHour = Int(floor(rs.timeIntervalSince(dayStart) / 3600))
        let reHour = Int(ceil(re.timeIntervalSince(dayStart)  / 3600))
        rs = cal.date(byAdding: .hour, value: rsHour, to: dayStart)!
        re = cal.date(byAdding: .hour, value: reHour, to: dayStart)!
    }

    // Cap at 03:00 next day.
    let cap3am = cal.date(byAdding: .hour, value: 27, to: cal.startOfDay(for: now))!
    re = min(re, cap3am)
    return (rs, re)
}

private func computeTimelineLayout(_ events: [CalEvent], now: Date) -> TimelineLayout {
    let (rs, re) = timeMap(events, now: now)
    let minutes = CGFloat(re.timeIntervalSince(rs) / 60)
    let width  = timelinePadL + minutes * pxPerMin + timelinePadR
    let height = max(timelineMinHeight, timeLineHeight(events.count))
    return TimelineLayout(rs: rs, re: re, width: width, height: height)
}

/// Whether the timeline should be replaced by the plain list: too many events,
/// or any event reaching outside the [earliest, latest] hour band of the day.
private func shouldUseFallback(_ events: [CalEvent], now: Date) -> Bool {
    if events.count > fallbackMaxEvents { return true }
    let cal = Calendar.current
    let dayStart = cal.startOfDay(for: now)
    let earliest = cal.date(byAdding: .hour, value: fallbackEarliestHour, to: dayStart)!
    let latest   = cal.date(byAdding: .hour, value: fallbackLatestHour,   to: dayStart)!
    return events.contains { $0.start < earliest || $0.end > latest }
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
    var events: [CalEvent] = []   // visible events, sorted by start
    var rs = Date()               // range start (left edge)
    var re = Date()               // range end (right edge)
    var focused: CalEvent?
    var onEventSelected: ((CalEvent) -> Void)?

    // y=0 at top, increasing downward — matches the flipped DrawCtx coordinate space.
    override var isFlipped: Bool { true }

    /// Time → x within the view (no clamping; the view width matches the range span).
    private func t2x(_ t: Date) -> CGFloat {
        timelinePadL + CGFloat(t.timeIntervalSince(rs) / 60) * pxPerMin
    }

    private var eventsTop: CGFloat { nowLabelH + firstEventPad }

    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        let row = Int(floor((loc.y - eventsTop) / rowH))
        guard row >= 0, row < events.count else { return }
        onEventSelected?(events[row])
    }

    override func resetCursorRects() {
        for i in events.indices {
            let y = eventsTop + CGFloat(i) * rowH
            addCursorRect(NSRect(x: 0, y: y, width: bounds.width, height: rowH), cursor: .pointingHand)
        }
    }

    private static let hourFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "H";     return f }()
    private static let timeFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f }()

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // No background fill — the white right column shows through.
        guard !events.isEmpty else { return }

        let now = Config.now
        let cal = Calendar.current
        let bottomY = bounds.height - hoursH   // top of the bottom hour-label band

        // Hour gridlines + axis labels (labels at the bottom).
        let lblAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: timelineFontSize - 2, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        var cur = rs
        while cur <= re {
            let x = t2x(cur)
            NSColor.separatorColor.setStroke()
            let grid = NSBezierPath()
            grid.move(to: NSPoint(x: x, y: nowLabelH))
            grid.line(to: NSPoint(x: x, y: bottomY))
            grid.lineWidth = 0.5
            grid.stroke()

            let lbl   = TimelineView.hourFmt.string(from: cur) as NSString
            let lblSz = lbl.size(withAttributes: lblAttrs)
            lbl.draw(at: NSPoint(x: x - lblSz.width / 2, y: bottomY + (nowLabelH - lblSz.height) / 2),
                     withAttributes: lblAttrs)
            cur = cal.date(byAdding: .hour, value: 1, to: cur)!
        }

        // "Now" marker — dot + time label at top, solid line through rows.
        if now >= rs && now <= re {
            let nx       = t2x(now)
            let dotR: CGFloat = 3
            let nowColor = NSColor.systemRed

            nowColor.withAlphaComponent(0.5).setStroke()
            let line = NSBezierPath()
            line.move(to: NSPoint(x: nx, y: nowLabelH / 2))
            line.line(to: NSPoint(x: nx, y: bottomY))
            line.lineWidth = 1
            line.stroke()

            nowColor.setFill()
            NSBezierPath(ovalIn: NSRect(x: nx - dotR, y: (nowLabelH - dotR * 2) / 2,
                                        width: dotR * 2, height: dotR * 2)).fill()

            let nowStr = TimelineView.timeFmt.string(from: now) as NSString
            let nowAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: timelineFontSize - 2, weight: .semibold),
                .foregroundColor: nowColor,
            ]
            let nowSz = nowStr.size(withAttributes: nowAttrs)
            nowStr.draw(at: NSPoint(x: nx + dotR + 3, y: (nowLabelH - nowSz.height) / 2),
                        withAttributes: nowAttrs)
        }

        // Precompute per-event layout so we can use it across passes.
        // titleRect width = actual rendered text width (capped at maxW), so white backgrounds
        // don't bleed into the now-line or beyond available space.
        // Morning titles (hour < 13): left-aligned after the time label, capped at maxTimelineTitleW.
        // Afternoon titles (hour ≥ 13): right-aligned to the event start (x1-6), capped at maxTimelineTitleW.
        struct EvLayout {
            let cy: CGFloat, x1: CGFloat, x2: CGFloat
            let color: NSColor, alpha: CGFloat
            let timeStr: NSString, timeAttrs: [NSAttributedString.Key: Any]
            let timeSz: NSSize, timeOrigin: NSPoint
            let titleStr: NSString, titleAttrs: [NSAttributedString.Key: Any]
            let titleRect: NSRect
        }
        var layouts: [EvLayout] = []
        for (i, ev) in events.enumerated() {
            let cy = eventsTop + CGFloat(i) * rowH + rowH / 2
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
            let isAfternoon = Calendar.current.component(.hour, from: ev.start) >= titleLeftThresholdHour
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
                let maxW  = min(maxTimelineTitleW, max(0, x1 - 6 - timelinePadL))
                let drawW = min(naturalW, maxW)
                titleRect = NSRect(x: x1 - 6 - drawW, y: cy - titleH / 2, width: drawW, height: titleH)
            } else {
                let drawW = min(naturalW, maxTimelineTitleW)
                titleRect = NSRect(x: afterTimeX, y: cy - titleH / 2, width: drawW, height: titleH)
            }

            layouts.append(EvLayout(cy: cy, x1: x1, x2: x2, color: color, alpha: alpha,
                                    timeStr: timeStr, timeAttrs: timeAttrs,
                                    timeSz: timeSz, timeOrigin: timeOrigin,
                                    titleStr: titleStr, titleAttrs: titleAttrs,
                                    titleRect: titleRect))
        }

        // Pass 1: white backgrounds behind text (sized to actual rendered width).
        NSColor.white.setFill()
        for l in layouts {
            NSBezierPath(rect: NSRect(origin: l.timeOrigin, size: l.timeSz).insetBy(dx: -2, dy: 0)).fill()
            NSBezierPath(rect: l.titleRect.insetBy(dx: -2, dy: 0)).fill()
        }

        // Pass 2: L-shapes on top of white backgrounds.
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

        // Pass 3: text on top of everything.
        for l in layouts {
            l.timeStr.draw(at: l.timeOrigin, withAttributes: l.timeAttrs)
            l.titleStr.draw(in: l.titleRect, withAttributes: l.titleAttrs)
        }
    }
}

// MARK: - Fallback list (mirror web/src/fallbackList.ts)

/// Flipped so the scrolling list grows from the top.
private final class FlippedStackView: NSStackView {
    override var isFlipped: Bool { true }
}

// MARK: - Reminder Window

final class ReminderWindow: NSWindow {
    private let event: CalEvent?          // triggering event (nil = opened without a reminder)
    private var nextEvent: CalEvent?      // event shown in the bottom slot / drives countdown + color
    private let visibleEvents: [CalEvent] // today's events, sorted by start
    private let now: Date
    private let useFallback: Bool
    private let layout: TimelineLayout?   // nil when the fallback list is shown

    private var countdownField: NSTextField?
    private var colonVisible   = true
    private var tickTimer: Timer?

    private var leftColumn: NSView?
    private var timelineView: TimelineView?
    private var selectedSlot: NSView?     // top slot — filled on timeline click
    private var nextSlotView: NSView?     // bottom slot — next event
    private var selectedEvent: CalEvent?

    /// True when opened via "Open Calendar" (no triggering reminder) — these get
    /// live-recreated on mock changes, unlike reminder pop-ups.
    var isCalendarWindow: Bool { event == nil }

    init(event: CalEvent?, todayEvents allEvents: [CalEvent]) {
        self.event = event
        let now = Config.now
        self.now = now

        // Visible = same-day events, sorted by start (mirror computeVisible).
        let cal = Calendar.current
        let visible = allEvents
            .filter { cal.isDate($0.start, inSameDayAs: now) }
            .sorted { $0.start < $1.start }
        self.visibleEvents = visible
        self.nextEvent     = event ?? visible.first { $0.end > now }

        let fallback = Config.forceFallback || shouldUseFallback(visible, now: now)
        self.useFallback = fallback

        let contentW: CGFloat
        let winH: CGFloat
        if fallback {
            self.layout = nil
            contentW = fallbackListW
            winH = max(winContentH,
                       rightColPadT + dateHeaderH + dateHeaderGap + timelineMinHeight + rightColPadB)
        } else {
            let l = computeTimelineLayout(visible, now: now)
            self.layout = l
            contentW = l.width
            winH = max(winContentH,
                       rightColPadT + dateHeaderH + dateHeaderGap + l.height + rightColPadB)
        }
        let winW = windowWidth(contentW)

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

        let accent = accentColor(for: nextEvent)
        buildUI(accent: accent)
        if event != nil, Config.soundEnabled { NSSound.playSystemSound("Glass") }
        startTickTimer()   // always: also drives the live time-scrubber refresh
    }

    /// Refresh the window in place when only the (simulated) clock moved — no
    /// recreation, since the window size is stable while scrubbing within a day.
    /// Recomputes the next event, rebuilds the bottom slot if it changed, and
    /// repaints the timeline's now-marker / colors / countdown / accent.
    func refreshForTimeChange() {
        let newNext = event ?? visibleEvents.first { $0.end > Config.now }
        if newNext != nextEvent {
            nextEvent = newNext
            if let slot = nextSlotView {
                slot.subviews.forEach { $0.removeFromSuperview() }
                countdownField = nil
                if let newNext { buildNextContent(in: slot, event: newNext) }
                else           { buildAllClear(in: slot) }
            }
        }
        leftColumn?.layer?.backgroundColor = accentColor(for: nextEvent).cgColor
        timelineView?.needsDisplay = true
        if nextEvent != nil { tick() }
    }

    // MARK: - UI

    private func buildUI(accent: NSColor) {
        let root = NSView()
        root.wantsLayer = true
        contentView = root
        root.frame = contentView?.bounds ?? .zero
        root.autoresizingMask = [.width, .height]

        // Left column — solid accent color.
        let left = NSView()
        left.translatesAutoresizingMaskIntoConstraints = false
        left.wantsLayer = true
        left.layer?.backgroundColor = accent.cgColor
        root.addSubview(left)

        // Right column — solid white.
        let right = NSView()
        right.translatesAutoresizingMaskIntoConstraints = false
        right.wantsLayer = true
        right.layer?.backgroundColor = NSColor.white.cgColor
        root.addSubview(right)

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
        titleField.preferredMaxLayoutWidth = leftW - leftColPad * 2
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

            titleField.topAnchor.constraint(equalTo: nextLbl.bottomAnchor, constant: 0),
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
        let dateField = NSTextField(labelWithString: fmt.string(from: now))
        dateField.translatesAutoresizingMaskIntoConstraints = false
        dateField.font      = NSFont.boldSystemFont(ofSize: timelineFontSize + 2)
        dateField.textColor = .labelColor
        right.addSubview(dateField)

        NSLayoutConstraint.activate([
            dateField.leadingAnchor.constraint(equalTo: right.leadingAnchor, constant: rightColPadL + dateHeaderIndent),
            dateField.topAnchor.constraint(equalTo: right.topAnchor, constant: rightColPadT),
        ])

        if useFallback {
            buildFallbackList(in: right, below: dateField)
        } else if let layout {
            let timeline = TimelineView()
            timeline.translatesAutoresizingMaskIntoConstraints = false
            timeline.events  = visibleEvents
            timeline.rs      = layout.rs
            timeline.re      = layout.re
            timeline.focused = nil
            timeline.onEventSelected = { [weak self] ev in self?.handleTimelineEventSelected(ev) }
            right.addSubview(timeline)
            self.timelineView = timeline

            NSLayoutConstraint.activate([
                timeline.leadingAnchor.constraint(equalTo: right.leadingAnchor, constant: rightColPadL),
                timeline.topAnchor.constraint(equalTo: dateField.bottomAnchor, constant: dateHeaderGap),
                timeline.widthAnchor.constraint(equalToConstant: layout.width),
                timeline.heightAnchor.constraint(equalToConstant: layout.height),
            ])
        }
    }

    // Plain scrolling list — each event's start time, title, and relative offset.
    private func buildFallbackList(in right: NSView, below dateField: NSView) {
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground    = true
        scroll.backgroundColor    = .white
        scroll.borderType         = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers  = true
        right.addSubview(scroll)

        let stack = FlippedStackView()
        stack.orientation = .vertical
        stack.alignment   = .leading
        stack.spacing     = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = stack

        let clip = scroll.contentView
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: clip.topAnchor),
            stack.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            stack.widthAnchor.constraint(equalTo: clip.widthAnchor),

            scroll.leadingAnchor.constraint(equalTo: right.leadingAnchor, constant: rightColPadL),
            scroll.topAnchor.constraint(equalTo: dateField.bottomAnchor, constant: dateHeaderGap),
            scroll.widthAnchor.constraint(equalToConstant: fallbackListW),
            scroll.bottomAnchor.constraint(equalTo: right.bottomAnchor, constant: -rightColPadB),
        ])

        if visibleEvents.isEmpty {
            let row = fallbackEmptyRow()
            stack.addArrangedSubview(row)   // add first — constraint needs a common ancestor
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        } else {
            for ev in visibleEvents {
                let row = fallbackRow(ev)
                stack.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            }
        }
    }

    /// Relative offset of an event from now: "now" while running, "in 1h 5m" when
    /// upcoming, empty for events that have already ended (those rows are dimmed).
    private func fallbackOffsetText(_ ev: CalEvent) -> String {
        if ev.start <= now && now < ev.end { return "now" }
        let secs = ev.start.timeIntervalSince(now)
        if secs <= 0 { return "" }   // ended
        return "in " + durString(minutes: Int(ceil(secs / 60)))
    }

    private func fallbackRow(_ ev: CalEvent) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        if ev.end <= now { row.alphaValue = 0.4 }   // dim ended events

        let timeFmt = DateFormatter(); timeFmt.dateFormat = "HH:mm"
        let time = NSTextField(labelWithString: timeFmt.string(from: ev.start))
        time.font          = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .bold)
        time.textColor     = NSColor(hex: "#000000")
        time.translatesAutoresizingMaskIntoConstraints = false
        time.setContentHuggingPriority(.required, for: .horizontal)
        time.setContentCompressionResistancePriority(.required, for: .horizontal)

        let title = NSTextField(labelWithString: ev.title)
        title.font          = NSFont.systemFont(ofSize: 13)
        title.textColor     = NSColor(hex: "#333333")
        title.lineBreakMode = .byTruncatingTail
        title.translatesAutoresizingMaskIntoConstraints = false
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let offset = NSTextField(labelWithString: fallbackOffsetText(ev))
        offset.font          = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        offset.textColor     = NSColor(hex: "#999999")
        offset.translatesAutoresizingMaskIntoConstraints = false
        offset.setContentHuggingPriority(.required, for: .horizontal)
        offset.setContentCompressionResistancePriority(.required, for: .horizontal)

        let sep = NSView()
        sep.translatesAutoresizingMaskIntoConstraints = false
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor(hex: "#f0f0f0").cgColor

        row.addSubview(time); row.addSubview(title); row.addSubview(offset); row.addSubview(sep)

        NSLayoutConstraint.activate([
            time.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 8),
            time.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            offset.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -8),
            offset.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            title.leadingAnchor.constraint(equalTo: time.trailingAnchor, constant: 8),
            title.trailingAnchor.constraint(lessThanOrEqualTo: offset.leadingAnchor, constant: -8),
            title.topAnchor.constraint(equalTo: row.topAnchor, constant: 5),
            title.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -5),

            sep.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            sep.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            sep.heightAnchor.constraint(equalToConstant: 1),
        ])
        return row
    }

    private func fallbackEmptyRow() -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        let label = NSTextField(labelWithString: "No events")
        label.font      = NSFont.systemFont(ofSize: 13)
        label.textColor = NSColor(hex: "#999999")
        label.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 8),
            label.topAnchor.constraint(equalTo: row.topAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -12),
        ])
        return row
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
        titleField.preferredMaxLayoutWidth = leftW - leftColPad * 2
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
        // Keep the timeline's "now" marker moving / event colors current.
        timelineView?.needsDisplay = true

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
