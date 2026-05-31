// Pure utility functions — string formatting and date manipulation.
// No layout constants, no DOM, no Canvas.

// MARK: - String

export function pad2(n: number): string {
  return String(n).padStart(2, "0");
}

export function hhmm(d: Date): string {
  return `${pad2(d.getHours())}:${pad2(d.getMinutes())}`;
}

// MARK: - Date

export function startOfDay(d: Date): Date {
  const r = new Date(d);
  r.setHours(0, 0, 0, 0);
  return r;
}
export function sameDay(a: Date, b: Date): boolean {
  return startOfDay(a).getTime() === startOfDay(b).getTime();
}
export function setHour(d: Date, h: number): Date {
  const r = new Date(d);
  r.setHours(h, 0, 0, 0);
  return r;
}
export function floorToMinute(d: Date): Date {
  const r = new Date(d);
  r.setSeconds(0, 0);
  r.setMinutes(0); // matches Swift date(bySetting:.minute, value: 0) — zeroes minutes
  return r;
}
export function addHours(d: Date, h: number): Date {
  return new Date(d.getTime() + h * 3_600_000);
}
