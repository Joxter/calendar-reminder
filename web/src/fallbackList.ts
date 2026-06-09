// Fallback right-column renderer — a plain HTML list of events instead of the
// canvas timeline. A debug/diagnostic view: just each event's start time and
// title, with a relative offset from the current (simulated) time. None of the
// timeline chrome — no duration, no hour grid, no now-marker. Fixed width.
// Web-only; not a Swift port target.

import { CalEvent, startsInSeconds } from "./model";
import { durString } from "./layout";
import { hhmm } from "./utils";

// Fixed content width of the fallback list (px). The window width is derived
// from this via windowWidth(); see script.ts.
export const fallbackListW = 300;

function el(tag: string, className: string, text?: string): HTMLElement {
  const e = document.createElement(tag);
  e.className = className;
  if (text !== undefined) e.textContent = text;
  return e;
}

/// Relative offset of an event from now: "now" while running, "in 1h 5m" when
/// upcoming, empty for events that have already ended (those rows are dimmed).
function offsetText(ev: CalEvent, now: Date): string {
  if (ev.start <= now && now < ev.end) return "now";
  const secs = startsInSeconds(ev, now);
  if (secs <= 0) return ""; // ended
  return "in " + durString(Math.ceil(secs / 60));
}

export function renderFallbackList(
  container: HTMLElement,
  p: { events: CalEvent[]; now: Date },
): void {
  if (p.events.length === 0) {
    container.replaceChildren(el("div", "fb-empty", "No events"));
    return;
  }
  const rows = p.events.map((ev) => {
    const done = ev.end <= p.now;
    const row = el("div", done ? "fb-row fb-done" : "fb-row");
    row.append(
      el("div", "fb-time", hhmm(ev.start)),
      el("div", "fb-title", ev.title),
      el("div", "fb-offset", offsetText(ev, p.now)),
    );
    return row;
  });
  container.replaceChildren(...rows);
}
