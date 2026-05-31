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
  offsetMinutes: number // minutes from `now`; negative = already started
  durationMinutes: number
}

export const mockEventDefs: MockEventDef[] = [
  { id: 'very_long', title: 'very long event with very long name, probably some broken import from another systems', offsetMinutes: 90, durationMinutes: 180 },
  { id: 'inprogress', title: 'All-hands', offsetMinutes: -20, durationMinutes: 60 },
  { id: 'verysoon', title: 'Standup', offsetMinutes: 1, durationMinutes: 15 },
  { id: 'soon', title: 'Design Review', offsetMinutes: 8, durationMinutes: 60 },
  { id: 'upcoming', title: 'Lunch', offsetMinutes: 30, durationMinutes: 60 },
  { id: 'overlap1', title: 'Sprint Planning', offsetMinutes: 65, durationMinutes: 60 },
  { id: 'overlap2', title: 'Retrospective', offsetMinutes: 90, durationMinutes: 60 },
  { id: 'later', title: '1:1 with Manager', offsetMinutes: 160, durationMinutes: 30 },
]

/// Builds CalEvents for the enabled mock ids, relative to `now`, sorted by start.
export function buildMockEvents(enabledIds: Set<string>, now: Date): CalEvent[] {
  return mockEventDefs
    .filter((d) => enabledIds.has(d.id))
    .map((d) => {
      const start = new Date(now.getTime() + d.offsetMinutes * 60_000)
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
