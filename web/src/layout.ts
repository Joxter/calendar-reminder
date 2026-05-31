// Pure layout math + constants — mirrors the top of ReminderWindow.swift.
// NO DOM, NO Canvas: this module transpiles to Swift verbatim. All rendering
// goes through DrawCtx (drawctx.ts); all measurement is done by the renderer.

import { CalEvent, startsInSeconds, durationSeconds } from './model'

// MARK: - Palette
// Web equivalents of the macOS semantic colors used in TimelineView (light mode),
// plus the explicit accent hexes from ReminderWindow.swift.
export const palette = {
  accentInProgress: '#dc2626', // red   — < urgentThreshold away
  accentSoon: '#2563eb',       // blue  — default
  accentNone: '#475569',       // gray  — no next event

  systemBlue: '#007aff',  // upcoming event
  systemGreen: '#34c759', // in-progress event
  systemRed: '#ff3b30',   // now marker

  label: '#000000',           // labelColor
  secondaryLabel: '#3c3c4399',// secondaryLabelColor (~0.6)
  tertiaryLabel: '#3c3c434d',  // tertiaryLabelColor (~0.3) — done events / "+N more"
  separator: '#3c3c434a',      // separatorColor — gridlines
  white: '#ffffff',
}

// MARK: - Layout constants (from ReminderWindow.swift)
export const axisH = 20
export const badgeH = 16
export const lPad = 10
export const rPad = 10

export const timelineFontSize = 13
export const rowH = timelineFontSize + 10 // 23

export const shapeStrokeW = 2
export const shapeCornerR = 4

export const leftColPad = 16
export const rightColPad = 4
export const winVPad = 16
export const panelGap = 16
export const dateHeaderH = 22
export const dateHeaderTop = 9
export const dateHeaderGap = 6

export const maxTimelineTitleW = 240

export const leftPanelTitleFontSz = 15
export const leftPanelMaxTitleLines = 2

export const winW = 720
export const leftW = 210
export const urgentThreshold = 120 // seconds

// MARK: - Font-metric approximation
// AppKit derives slot heights from real font metrics; on the web we approximate
// line height as size * 1.21 (rounded). This is the prototype tuning knob.
export function lineHeight(size: number): number {
  return Math.ceil(size * 1.21)
}

const calLblLineH = lineHeight(10)
const infoLineH = lineHeight(11)
const nextLblLineH = lineHeight(9)
const timerLineH = lineHeight(52)
export const leftPanelTitleMaxH = lineHeight(leftPanelTitleFontSz) * leftPanelMaxTitleLines + 4

// Selected-event slot (top): calLabel + 4 + title + 6 + info
export const selectedSlotH = calLblLineH + 4 + leftPanelTitleMaxH + 6 + infoLineH
// Next-event slot (bottom): nextLabel + title + 1 + timer
export const nextSlotH = nextLblLineH + leftPanelTitleMaxH + 1 + timerLineH
// Constant window content height — both slots always reserved.
export const winContentH = winVPad + selectedSlotH + panelGap + nextSlotH + winVPad

// Right column geometry.
export const rightW = winW - leftW
// Timeline canvas height = right column minus the date header band and bottom pad.
export const timelineH = winContentH - dateHeaderTop - dateHeaderH - dateHeaderGap - rightColPad
// Timeline canvas width = right column minus its insets.
export const timelineW = rightW - rightColPad * 2

// MARK: - Date helpers
export function startOfDay(d: Date): Date {
  const r = new Date(d)
  r.setHours(0, 0, 0, 0)
  return r
}
export function sameDay(a: Date, b: Date): boolean {
  return startOfDay(a).getTime() === startOfDay(b).getTime()
}
export function setHour(d: Date, h: number): Date {
  const r = new Date(d)
  r.setHours(h, 0, 0, 0)
  return r
}
export function floorToMinute(d: Date): Date {
  const r = new Date(d)
  r.setSeconds(0, 0)
  r.setMinutes(0) // matches Swift date(bySetting:.minute, value: 0) — zeroes minutes
  return r
}
export function addHours(d: Date, h: number): Date {
  return new Date(d.getTime() + h * 3_600_000)
}

// MARK: - Formatters (pure)

/// "Xh Ym", capped at 23:59.
export function durString(minutes: number): string {
  if (minutes <= 0) return ''
  const m = Math.min(minutes, 23 * 60 + 59)
  const h = Math.floor(m / 60)
  const rem = m % 60
  if (h > 0) return rem > 0 ? `${h}h ${rem}m` : `${h}h`
  return `${rem}m`
}

/// "H:MM" when >= 1h away, "MM:SS" otherwise, "NOW" once started.
export function countdownText(rawSecs: number): string {
  const secs = Math.max(0, rawSecs)
  if (secs <= 0) return 'NOW'
  const totalMin = Math.floor(secs / 60)
  if (totalMin >= 60) {
    return `${Math.floor(totalMin / 60)}:${String(totalMin % 60).padStart(2, '0')}`
  }
  return `${String(totalMin).padStart(2, '0')}:${String(Math.floor(secs % 60)).padStart(2, '0')}`
}

export function pad2(n: number): string {
  return String(n).padStart(2, '0')
}
export function hhmm(d: Date): string {
  return `${pad2(d.getHours())}:${pad2(d.getMinutes())}`
}

/// Left-column accent: gray when no next, red when imminent, blue otherwise.
export function accentColor(next: CalEvent | null, now: Date): string {
  if (!next) return palette.accentNone
  return startsInSeconds(next, now) <= urgentThreshold ? palette.accentInProgress : palette.accentSoon
}

// MARK: - Day selection

export interface VisibleEvents {
  visible: CalEvent[]      // every event starting on `now`'s day, in order
  next: CalEvent | null    // first not-yet-ended event (drives the left column)
}

/// All events that start today — no trimming, no collapse rows.
export function computeVisible(all: CalEvent[], now: Date, triggering: CalEvent | null = null): VisibleEvents {
  const visible = all.filter((e) => sameDay(e.start, now))
  return {
    visible,
    next: triggering ?? visible.find((e) => e.end > now) ?? null,
  }
}

// MARK: - Time → x mapping

export interface TimeMap {
  rs: Date
  re: Date
  t2x: (t: Date) => number
}

/// Window is at least 08:00–20:00, extended to fit events, capped at 03:00 next day.
export function timeMap(events: CalEvent[], now: Date, width: number): TimeMap {
  const barW = width - lPad - rPad
  let rs = setHour(now, 8)
  let re = setHour(now, 20)
  if (events.length > 0) {
    rs = new Date(Math.min(rs.getTime(), floorToMinute(events[0].start).getTime()))
    re = new Date(Math.max(re.getTime(), floorToMinute(events[events.length - 1].end).getTime()))
  }
  const cap3am = addHours(startOfDay(now), 27)
  re = new Date(Math.min(re.getTime(), cap3am.getTime()))

  const totSecs = Math.max((re.getTime() - rs.getTime()) / 1000, 1)
  const t2x = (t: Date) => {
    const frac = (t.getTime() - rs.getTime()) / 1000 / totSecs
    return lPad + Math.max(0, Math.min(barW, frac * barW))
  }
  return { rs, re, t2x }
}

/// Hour gridline timestamps spanning [rs, re].
export function hourGridlines(rs: Date, re: Date): Date[] {
  const out: Date[] = []
  let cur = rs
  while (cur.getTime() <= re.getTime()) {
    out.push(cur)
    cur = addHours(cur, 1)
  }
  return out
}

/// Hit-test a click at canvas y to an event index (mirrors mouseDown).
export function rowAt(y: number, count: number): number | null {
  const row = Math.floor((y - axisH) / rowH)
  if (row < 0 || row >= count) return null
  return row
}

export { startsInSeconds, durationSeconds }
