# Calendar Blocker

A macOS desktop app that shows an aggressive reminder window when a Google Calendar event is about to start. No OAuth, no Google API SDK — just a private iCal feed URL.

---

## How it works

1. A background thread polls your Google Calendar iCal feed on a configurable interval (default 5 min).
2. When an event falls within the warning window (default 10 min before start), a reminder window appears on top of all other windows and steals focus.
3. The same event is never shown twice in the same session (dedup by title + start time).
4. Events that started up to `STARTED_GRACE` seconds ago are still shown if a poll cycle missed them.
5. The main thread runs a persistent `tkinter` event loop so the app stays responsive between polls — no spinning beach ball.

---

## Setup

### Requirements

- macOS (uses `afplay` for sound, `SF Pro` fonts for UI)
- Python 3.11+
- [uv](https://docs.astral.sh/uv/)

### Install

```bash
git clone <repo>
cd calendar-blocker
uv sync
```

### Get your iCal URL

1. Open [calendar.google.com](https://calendar.google.com)
2. Click **⋮** next to your calendar → **Settings and sharing**
3. Scroll to **Secret address in iCal format**
4. Copy the URL (looks like `https://calendar.google.com/calendar/ical/you%40gmail.com/private-XXXXX/basic.ics`)

### Configure

Copy `.env` and fill in your URL:

```bash
ICAL_URL=https://calendar.google.com/calendar/ical/you%40gmail.com/private-XXXXX/basic.ics
POLL_INTERVAL=300        # seconds between calendar fetches
WARNING_THRESHOLD=600    # seconds before event start to show reminder
STARTED_GRACE=300        # seconds after event start to still show reminder
```

### Run

```bash
uv run python main.py
```

On startup a reminder window is shown immediately for the next real upcoming event (if any), so you can verify the UI without waiting for the first poll cycle.

---

## Reminder window

The window is 720 × (dynamic height) px, always on top, steals keyboard focus.  
It is split into two columns separated by a 1 px hairline.

### Left column (210 px, white)

| Element | Detail |
|---|---|
| Urgency badge | Coloured pill: amber `#f59e0b` / orange `#f97316` / red `#ef4444` |
| Event title | SF Pro Display 16 pt bold, wraps to multiple lines |
| Duration | SF Pro Text 12 pt, format `h:mm` (e.g. `0:30`, `1:00`, `1:30`) |
| Dismiss button | Label-based button (not `tk.Button` — macOS ignores bg on native buttons), accent colour, hover darkens 18%, bottom-right of column |

Dismiss also responds to **Esc**, **Return**, and the window close button.

### Right column (remaining width, `#f5f5f7`)

**Date header** — weekday and date (e.g. `Sunday, May 17`), SF Pro Text 11 pt bold.

**Timeline canvas** — Gantt-style, one row per event sorted by start time.

#### Time axis

- Fixed range **08:00 – 18:00** local time, extended automatically if any event falls outside.
- Hour labels (`8`, `9`, … `18`) in SF Pro Text 8 pt, light grey `#c7c7cc`.
- Vertical gridlines `#ebebeb` at each hour.
- **"Now" marker** — dashed vertical line `#ffb3af` (light pink), dash pattern (2, 5). Subtle, not distracting.

#### Event rows

Row height: **22 px**.  
Each event renders three elements at the same font size (SF Pro Text 11 pt):

1. **Time badge** — filled rectangle (`40 × 16 px`) at `t2x(start)`.  
   Corners: TL, TR, BL rounded (radius 3 px); **BR is square** so it connects flush with the underline.  
   Contains `HH:MM` in white 11 pt bold, centered.

2. **Duration underline** — 2 px tall filled rectangle, same colour as the badge, from `t2x(start)` to `t2x(end)`.  
   The badge is drawn on top, covering the underline's left end — they form one solid L-shaped mark.

3. **Title + duration** — `"{title}  {h:mm}"`, SF Pro Text 11 pt (bold for the focused event).  
   - Events starting **before 13:00**: title appears to the **right** of the badge (`anchor="w"`).  
   - Events starting **at or after 13:00**: title appears to the **left** of the badge (`anchor="e"`) so late-day events have room on the right side of the timeline.

#### Event state colours

| State | Badge / underline | Title |
|---|---|---|
| Done (ended) | `#6e6e73` medium grey | `#3a3a3c` dark grey |
| Active (in progress) | `#34c759` green | `#1d1d1f` |
| **Focused** (this reminder) | accent colour | `#1d1d1f` bold |
| Overlapping | `#ff9f0a` orange | `#1d1d1f` |
| Upcoming | `#007aff` blue | `#1d1d1f` |

**Overlapping events** — any two events whose time ranges intersect both receive the orange colour. Overlap is detected pairwise; the bars appear in separate rows but share the same x-range, making the conflict immediately visible.

---

## Sound

Plays `/System/Library/Sounds/Glass.aiff` via `afplay` (non-blocking subprocess) when the reminder window appears. Silent on non-macOS or if `afplay` is missing.

---

## Project structure

```
calendar-blocker/
├── main.py              — entry point; persistent tkinter event loop + polling thread
├── calendar_checker.py  — iCal fetch/parse; returns upcoming events, today's events, next event
├── reminder_window.py   — two-column Toplevel window with Gantt timeline
├── config.py            — reads .env / environment variables
├── .env                 — local config (git-ignored)
├── pyproject.toml       — uv/hatchling project definition
└── uv.lock              — pinned dependency lockfile
```

### Key architecture decisions

- **Persistent mainloop** — `main.py` runs one `root.mainloop()` forever. Polling sleeps in a daemon thread. Reminder windows are `Toplevel` children, not separate `Tk()` instances. This avoids the macOS spinning-ball caused by blocking or withdrawing the root window.
- **Thread → UI bridge** — the polling thread never touches tkinter directly. It calls `root.after(0, lambda: show_reminder(...))` to schedule window creation on the main thread.
- **Single HTTP fetch per cycle** — `fetch_calendar_data()` makes one request and returns `(upcoming, today, next_event)` so the poll loop never fetches the calendar twice per cycle.
- **Label-based buttons** — `tk.Button` ignores the `bg` parameter on macOS (Aqua overrides it). All coloured buttons are `tk.Label` widgets with `<Button-1>`, `<Enter>`, `<Leave>` bindings.
- **Rounded badge corners** — drawn with `canvas.create_polygon` using manually computed arc points (no external drawing library). BR corner is left square so it meets the underline cleanly.

---

## Configuration reference

| Variable | Default | Description |
|---|---|---|
| `ICAL_URL` | — | Private iCal feed URL (required) |
| `POLL_INTERVAL` | `300` | Seconds between calendar fetches |
| `WARNING_THRESHOLD` | `600` | Seconds before event start to trigger reminder |
| `STARTED_GRACE` | `300` | Seconds after event start to still show reminder |
