// Mirrors Sources/CalendarBlocker/ICalParser.swift (CalEvent) and
// Config.mockEventDefs. Kept dependency-free so it transpiles to Swift directly.

export interface CalEvent {
  title: string;
  start: Date;
  end: Date;
  uid: string | null;
  calendarName: string | null;
  calendarEmail: string | null;
}

export function startsInSeconds(ev: CalEvent, now: Date): number {
  return (ev.start.getTime() - now.getTime()) / 1000;
}

export function durationSeconds(ev: CalEvent): number {
  return (ev.end.getTime() - ev.start.getTime()) / 1000;
}

// MARK: - Mock events (mirrors Config.mockEventDefs)

export interface MockEventDef {
  id: string;
  title: string;
  startMinute: number; // absolute minute of the day (0..1439)
  durationMinutes: number;
}

const hm = (h: number, m = 0) => h * 60 + m; // minute-of-day helper

export const mockEventDefs: MockEventDef[] = [
  {
    id: "Crazy early",
    title: "Crazy early",
    startMinute: hm(2, 30),
    durationMinutes: 42,
  },
  {
    id: "Standup",
    title: "Standup",
    startMinute: hm(9, 30),
    durationMinutes: 15,
  },
  {
    id: "Ampiwise: Standup",
    title: "Ampiwise: Standup",
    startMinute: hm(10, 15),
    durationMinutes: 15,
  },
  {
    id: "Full-stack guild: Sptint planning",
    title: "Full-stack guild: Sptint planning",
    startMinute: hm(10, 30),
    durationMinutes: 45,
  },
  {
    id: "1-1 Alex, Nikolai",
    title: "1-1 Alex, Nikolai",
    startMinute: hm(10, 30),
    durationMinutes: 30,
  },
  {
    id: "Lunch",
    title: "Lunch",
    startMinute: hm(12, 9),
    durationMinutes: 60,
  },
  { id: "ex1", title: "ex1", startMinute: hm(13, 0), durationMinutes: 15 },
  { id: "ex2", title: "ex2", startMinute: hm(13, 0), durationMinutes: 15 },
  { id: "ex3", title: "ex3", startMinute: hm(13, 0), durationMinutes: 15 },
  { id: "ex4", title: "ex4", startMinute: hm(13, 0), durationMinutes: 15 },
  { id: "ex5", title: "ex5", startMinute: hm(13, 0), durationMinutes: 15 },
  { id: "ex6", title: "ex6", startMinute: hm(13, 0), durationMinutes: 15 },
  {
    id: "very long event with very long name, probably some broken import from another systems",
    title:
      "very long event with very long name, probably some broken import from another systems",
    startMinute: hm(14, 0),
    durationMinutes: 60,
  },
  {
    id: "Monthly update, 152min",
    title: "Monthly update, 152min",
    startMinute: hm(16, 15),
    durationMinutes: 152,
  },
  {
    id: "Very late WTF!? and 52 min!",
    title: "Very late WTF!?",
    startMinute: hm(23, 23),
    durationMinutes: 52,
  },
];

/// Builds CalEvents for the enabled mock ids on `day` (start-of-day), sorted by start.
export function buildMockEvents(
  enabledIds: Set<string>,
  day: Date,
): CalEvent[] {
  return mockEventDefs
    .filter((d) => enabledIds.has(d.id))
    .map((d) => {
      const start = new Date(day.getTime() + d.startMinute * 60_000);
      const end = new Date(start.getTime() + d.durationMinutes * 60_000);
      return {
        title: d.title,
        start,
        end,
        uid: `mock_${d.id}`,
        calendarName: "Mock",
        calendarEmail: null,
      } as CalEvent;
    })
    .sort((a, b) => a.start.getTime() - b.start.getTime());
}
