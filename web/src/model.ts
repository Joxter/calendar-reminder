// Mirrors Sources/CalendarBlocker/ICalParser.swift (CalEvent) and
// Config.mockEventDefs. Kept dependency-free so it transpiles to Swift directly.

export interface CalEvent {
  title: string
  start: Date
  end: Date
  uid: string | null
  calendarName: string | null
  calendarEmail: string | null
}

export function startsInSeconds(ev: CalEvent, now: Date): number {
  return (ev.start.getTime() - now.getTime()) / 1000
}

export function durationSeconds(ev: CalEvent): number {
  return (ev.end.getTime() - ev.start.getTime()) / 1000
}

// MARK: - Mock events (mirrors Config.mockEventDefs)

export interface MockEventDef {
  id: string
  title: string
  startMinute: number // absolute minute of the day (0..1439)
  durationMinutes: number
}

const hm = (h: number, m = 0) => h * 60 + m // minute-of-day helper

export const mockEventDefs: MockEventDef[] = [
  { id: 'verysoon', title: 'Standup', startMinute: hm(9, 0), durationMinutes: 15 },
  { id: 'inprogress', title: 'All-hands', startMinute: hm(9, 30), durationMinutes: 60 },
  { id: 'soon', title: 'Design Review', startMinute: hm(11, 0), durationMinutes: 60 },
  { id: 'upcoming', title: 'Lunch', startMinute: hm(12, 30), durationMinutes: 60 },
  { id: 'overlap1', title: 'Sprint Planning', startMinute: hm(14, 0), durationMinutes: 60 },
  { id: 'overlap2', title: 'Retrospective', startMinute: hm(14, 30), durationMinutes: 60 },
  { id: 'later', title: '1:1 with Manager', startMinute: hm(16, 0), durationMinutes: 30 },
  { id: 'very_long', title: 'very long event with very long name, probably some broken import from another systems', startMinute: hm(17, 0), durationMinutes: 180 },
]

/// Builds CalEvents for the enabled mock ids on `day` (start-of-day), sorted by start.
export function buildMockEvents(enabledIds: Set<string>, day: Date): CalEvent[] {
  return mockEventDefs
    .filter((d) => enabledIds.has(d.id))
    .map((d) => {
      const start = new Date(day.getTime() + d.startMinute * 60_000)
      const end = new Date(start.getTime() + d.durationMinutes * 60_000)
      return {
        title: d.title,
        start,
        end,
        uid: `mock_${d.id}`,
        calendarName: 'Mock',
        calendarEmail: null,
      } as CalEvent
    })
    .sort((a, b) => a.start.getTime() - b.start.getTime())
}
