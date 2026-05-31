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
// Events starting at or after this hour get the title drawn to the LEFT of the start marker.
export const titleLeftThresholdHour = 13

export const leftPanelTitleFontSz = 15
export const leftPanelMaxTitleLines = 2

export const leftW = 210
export const urgentThreshold = 120 // seconds

// MARK: - Timeline geometry knobs
export const pxPerHour = 40                              // fixed horizontal scale
export const defaultHourRange: [number, number] = [8, 20] // guaranteed visible hours
export const axisPaddingMin = 30                          // extra minutes before first / after last event
export const timelinePadL = 10                            // px — left axis inset
export const timelinePadR = 10                            // px — right axis inset
export const timelineMinHeight = 80                       // px — canvas never shorter than this

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

// winW and timeline dimensions are now dynamic — see computeTimelineDimensions().

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

const pxPerMin = pxPerHour / 60

/// Computes the visible time range and a t→x function based on fixed pxPerHour scale.
/// Range is at least defaultHourRange, extended by axisPaddingMin on each side to
/// cover all event starts/ends.
export function timeMap(events: CalEvent[], now: Date): TimeMap {
  let rs = setHour(now, defaultHourRange[0])
  let re = setHour(now, defaultHourRange[1])

  if (events.length > 0) {
    const paddingMs = axisPaddingMin * 60_000
    const earliest = new Date(events[0].start.getTime() - paddingMs)
    const latest   = new Date(events[events.length - 1].end.getTime() + paddingMs)
    rs = new Date(Math.min(rs.getTime(), earliest.getTime()))
    re = new Date(Math.max(re.getTime(), latest.getTime()))
  }

  // Snap to whole hours for clean gridlines.
  rs = setHour(now, Math.floor((rs.getTime() - startOfDay(now).getTime()) / 3_600_000))
  re = addHours(setHour(now, Math.ceil((re.getTime() - startOfDay(now).getTime()) / 3_600_000)), 0)

  // Cap at 03:00 next day.
  re = new Date(Math.min(re.getTime(), addHours(startOfDay(now), 27).getTime()))

  const t2x = (t: Date) =>
    timelinePadL + (t.getTime() - rs.getTime()) / 60_000 * pxPerMin

  return { rs, re, t2x }
}

/// Timeline canvas width derived from the time range.
export function timelineWidth(rs: Date, re: Date): number {
  const minutes = (re.getTime() - rs.getTime()) / 60_000
  return timelinePadL + minutes * pxPerMin + timelinePadR
}

/// Timeline canvas height derived from event count.
export function timelineHeight(eventCount: number): number {
  return Math.max(timelineMinHeight, axisH + eventCount * rowH + axisH)
}

/// Full window width = left column + right padding + timeline.
export function windowWidth(tlWidth: number): number {
  return leftW + rightColPad * 2 + tlWidth
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
