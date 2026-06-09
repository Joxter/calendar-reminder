// Orchestrator: builds the reminder-window mock, wires the pure-HTML devtools,
// and drives the calendar render loop. Calendar rendering itself lives in the
// transpilable modules (layout / timeline / leftColumn); this file is web glue.

import { CalEvent, buildMockEvents, mockEventDefs } from "./model";
import {
  computeVisible,
  shouldUseFallback,
  rowAt,
  computeTimelineLayout,
  windowWidth,
  winContentH,
  leftW,
  leftColPadT,
  leftColPadR,
  leftColPadB,
  leftColPadL,
  rightColPadT,
  rightColPadR,
  rightColPadB,
  rightColPadL,
  dateHeaderH,
  dateHeaderGap,
  dateHeaderIndent,
  timelineMinHeight,
  renderTimeline,
} from "./layout";
import { startOfDay, pad2 } from "./utils";
import { CanvasDrawCtx } from "./canvas";
import { renderLeftColumn } from "./leftColumn";
import { renderFallbackList, fallbackListW } from "./fallbackList";

// MARK: - Debug log
const debugLog = {
  log(message: string, type: "info" | "error" | "success" = "info") {
    const logEl = document.getElementById("debug-log");
    if (!logEl) return;
    const entry = document.createElement("div");
    entry.className = `dev-log-entry ${type}`;
    entry.textContent = `[${new Date().toLocaleTimeString()}] ${message}`;
    logEl.appendChild(entry);
    logEl.scrollTop = logEl.scrollHeight;
    while (logEl.children.length > 20) logEl.removeChild(logEl.firstChild!);
  },
};

// MARK: - State
const ALL_IDS = mockEventDefs.map((d) => d.id);
const STORAGE_KEY = "cb.enabledEvents";
const FALLBACK_KEY = "cb.fallback";

/// Persisted fallback-list (debug view) toggle.
function loadFallback(): boolean {
  return localStorage.getItem(FALLBACK_KEY) === "true";
}

/// Persisted set of enabled mock-event ids (falls back to "all enabled").
function loadEnabled(): Set<string> {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (raw) {
      const ids = JSON.parse(raw) as string[];
      return new Set(ids.filter((id) => ALL_IDS.includes(id))); // drop stale ids
    }
  } catch {
    /* ignore corrupt storage */
  }
  return new Set(ALL_IDS);
}

function saveEnabled() {
  localStorage.setItem(STORAGE_KEY, JSON.stringify([...state.enabled]));
}

function nowMinuteOfDay(): number {
  const d = new Date();
  return d.getHours() * 60 + d.getMinutes();
}

const state = {
  enabled: loadEnabled(),
  minuteOfDay: nowMinuteOfDay(), // simulated time-of-day (0..1439), absolute
  events: [] as CalEvent[],
  selected: null as CalEvent | null,
  fallback: loadFallback(), // debug: render right column as a plain list
};

let ctx: CanvasDrawCtx;
let leftEl: HTMLElement;
let dateEl: HTMLElement;
let canvasEl: HTMLCanvasElement;
let fallbackEl: HTMLElement;

const dateFmt = new Intl.DateTimeFormat(undefined, {
  weekday: "long",
  month: "short",
  day: "numeric",
});

/// Today at the simulated time-of-day.
function simulatedNow(): Date {
  return new Date(startOfDay(new Date()).getTime() + state.minuteOfDay * 60_000);
}

/// Rebuilds the (time-independent) mock events. Call on toggle/reset only —
/// events have fixed absolute times; scrubbing the clock does not move them.
function rebuildEvents() {
  state.events = buildMockEvents(state.enabled, startOfDay(new Date()));
  state.selected = null;
  render();
}

function minuteToHHMM(min: number): string {
  return `${pad2(Math.floor(min / 60))}:${pad2(min % 60)}`;
}
function hhmmToMinute(s: string): number {
  const [h, m] = s.split(":").map(Number);
  return h * 60 + m;
}

function render() {
  const now = simulatedNow();
  const vis = computeVisible(state.events, now);

  const winEl = document.getElementById("window")!;
  dateEl.textContent = dateFmt.format(now);
  renderLeftColumn(leftEl, { selected: state.selected, next: vis.next, now });

  // Fallback engages on the debug toggle, or automatically when the events make
  // the timeline impractical (too many, or reaching outside the day's band).
  const useFallback = state.fallback || shouldUseFallback(vis.visible, now);

  if (useFallback) {
    // Plain list, fixed width. Height is locked to the timeline's minimum
    // window height; the list scrolls (CSS) when events overflow.
    const fixedH = Math.max(
      winContentH,
      rightColPadT + dateHeaderH + dateHeaderGap + timelineMinHeight + rightColPadB,
    );
    canvasEl.style.display = "none";
    fallbackEl.style.display = "flex";
    fallbackEl.style.width = `${fallbackListW}px`;
    fallbackEl.style.marginLeft = `${rightColPadL}px`;
    renderFallbackList(fallbackEl, { events: vis.visible, now });
    winEl.style.width = `${windowWidth(fallbackListW)}px`;
    winEl.style.height = `${fixedH}px`;
    return;
  }

  canvasEl.style.display = "block";
  fallbackEl.style.display = "none";

  const layout = computeTimelineLayout(vis.visible, now);

  // Resize DOM elements to fit content.
  const rightColH =
    rightColPadT + dateHeaderH + dateHeaderGap + layout.height + rightColPadB;
  const winH = Math.max(winContentH, rightColH);
  winEl.style.width = `${windowWidth(layout.width)}px`;
  winEl.style.height = `${winH}px`;
  canvasEl.style.width = `${layout.width}px`;
  canvasEl.style.height = `${layout.height}px`;
  ctx.setupHiDPI();

  ctx.clear();
  renderTimeline(ctx, {
    events: vis.visible,
    focused: state.selected,
    now,
    layout,
  });
}

// MARK: - Window dimensions (static parts only; dynamic parts set in render())
function applyStaticDimensions() {

  leftEl.style.width = `${leftW}px`;
  leftEl.style.padding = `${leftColPadT}px ${leftColPadR}px ${leftColPadB}px ${leftColPadL}px`;

  dateEl.style.margin = `${rightColPadT}px 0 ${dateHeaderGap}px ${rightColPadL + dateHeaderIndent}px`;
  dateEl.style.height = `${dateHeaderH}px`;
  dateEl.style.fontSize = `15px`;

  canvasEl.style.marginLeft = `${rightColPadL}px`;
}

// MARK: - Dev tools
function buildMockControls() {
  const host = document.getElementById("mock-events")!;
  for (const def of mockEventDefs) {
    const row = document.createElement("div");
    row.className = "mock-row";
    const cb = document.createElement("input");
    cb.type = "checkbox";
    cb.id = `mock-${def.id}`;
    cb.checked = state.enabled.has(def.id);
    cb.addEventListener("change", () => {
      if (cb.checked) state.enabled.add(def.id);
      else state.enabled.delete(def.id);
      saveEnabled();
      debugLog.log(`${cb.checked ? "enabled" : "disabled"} "${def.id}"`);
      rebuildEvents();
    });
    const label = document.createElement("label");
    label.htmlFor = cb.id;
    label.textContent = `${def.id} (${minuteToHHMM(def.startMinute)})`;
    row.append(cb, label);
    host.appendChild(row);
  }
}

function wireTimeControls() {
  const range = document.getElementById("time-range") as HTMLInputElement;
  const input = document.getElementById("time-input") as HTMLInputElement;
  const apply = (v: number) => {
    state.minuteOfDay = Math.max(0, Math.min(1439, v));
    range.value = String(state.minuteOfDay);
    input.value = minuteToHHMM(state.minuteOfDay);
    render(); // events are fixed; only the simulated clock moves
  };
  range.addEventListener("input", () => apply(Number(range.value)));
  input.addEventListener("change", () => {
    if (input.value) apply(hhmmToMinute(input.value));
  });

  document.getElementById("reset-btn")!.addEventListener("click", () => {
    state.enabled = new Set(ALL_IDS);
    saveEnabled();
    for (const def of mockEventDefs) {
      (document.getElementById(`mock-${def.id}`) as HTMLInputElement).checked =
        state.enabled.has(def.id);
    }
    rebuildEvents();
    apply(nowMinuteOfDay());
    debugLog.log("reset", "info");
  });

  apply(state.minuteOfDay); // sync both inputs to the initial value
}

function wireFallbackToggle() {
  const cb = document.getElementById("fallback-toggle") as HTMLInputElement;
  cb.checked = state.fallback;
  cb.addEventListener("change", () => {
    state.fallback = cb.checked;
    localStorage.setItem(FALLBACK_KEY, String(cb.checked));
    debugLog.log(`fallback list ${cb.checked ? "on" : "off"}`);
    render();
  });
}

function wireCanvasSelection() {
  canvasEl.addEventListener("click", (e) => {
    const rect = canvasEl.getBoundingClientRect();
    const y = e.clientY - rect.top;
    const now = simulatedNow();
    const vis = computeVisible(state.events, now);
    const row = rowAt(y, vis.visible.length);
    if (row == null) return;
    const ev = vis.visible[row];
    state.selected = state.selected === ev ? null : ev; // toggle
    render();
  });
}

// MARK: - Init
function init() {
  leftEl = document.getElementById("left-column")!;
  dateEl = document.getElementById("date-header")!;
  canvasEl = document.getElementById("timeline") as HTMLCanvasElement;
  fallbackEl = document.getElementById("fallback-list")!;

  // canvasEl.style.background = 'green';

  applyStaticDimensions();
  ctx = new CanvasDrawCtx(canvasEl);

  buildMockControls();
  rebuildEvents(); // build fixed events before the first render
  wireTimeControls(); // also performs the initial render via apply()
  wireCanvasSelection();
  wireFallbackToggle();

  debugLog.log("App initialized", "success");
}

document.addEventListener("DOMContentLoaded", init);
