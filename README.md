# Calendar Blocker

A native macOS app (Swift + AppKit) that shows an aggressive reminder window when a Google Calendar event is about to start. No OAuth, no Google API SDK — just private iCal feed URLs. Supports multiple calendars simultaneously. Includes a menu bar icon with a live countdown to your next event.

---

## How it works

1. A background timer polls one or more Google Calendar iCal feeds every 60 seconds.
2. When an event falls within the warning window (default 10 min before start), a reminder window appears on top of all other windows and steals focus.
3. The same event is never shown twice in the same session. Events that appear in multiple calendar feeds are deduplicated by UID so they only appear once.
4. Events that started up to a few minutes ago are still shown if a poll cycle missed them.
5. Recurring events (RRULE) are fully expanded — daily, weekly, monthly, and yearly patterns are supported.
6. A menu bar icon shows the next event title and an animated live countdown; clicking it opens a menu with settings and a Quit option.

---

## Setup

### Requirements

- macOS 13+
- Xcode command-line tools (`xcode-select --install`)

### Get your iCal URL

1. Open [calendar.google.com](https://calendar.google.com)
2. Click **⋮** next to your calendar → **Settings and sharing**
3. Scroll to **Secret address in iCal format**
4. Copy the URL (looks like `https://calendar.google.com/calendar/ical/you%40gmail.com/private-XXXXX/basic.ics`)

### Configure

Run the app and click the calendar icon in the menu bar → **Set Calendar URLs…** Paste one iCal URL per line (one calendar per line) and press **Save**. All URLs are stored in `UserDefaults` and persist across launches.

### Run

```bash
./run.sh
```

Builds a release binary and launches the app.

### Development (auto-restart on save)

```bash
./watch.sh
```

Watches `Sources/` for `.swift` changes and hot-reloads the app automatically.

---

## Menu bar icon

The status bar item shows a calendar SF Symbol and a live countdown label. The countdown updates every 15 seconds, aligned to wall-clock boundaries (`:00` / `:15` / `:30` / `:45`), so the displayed minute is always the closest rounded minute rather than a ceiling — drift is negligible.

| State                             | Symbol                 | Colour                   |
| --------------------------------- | ---------------------- | ------------------------ |
| Event in progress or just started | `calendar.badge.clock` | Red                      |
| < 5 min away                      | `calendar.badge.clock` | Orange                   |
| Further away                      | `calendar`             | Secondary grey           |
| No events today                   | `calendar`             | Secondary grey, no label |

When any test/mock setting is active a `·` is appended to the label, so it's obvious you're not looking at live data.

Clicking the icon shows a dropdown:

| Item                      | Action                                                                              |
| ------------------------- | ----------------------------------------------------------------------------------- |
| Event title · start time  | Read-only, shows the next upcoming event                                            |
| **Set Calendar URLs…** ⌘, | Opens a multi-line dialog; paste one iCal URL per line                              |
| **Remind me** ▶           | Submenu: 5 / 10 / 15 / 30 minutes before                                            |
| **Sound** ✓               | Toggle the Glass sound on reminder                                                  |
| **Open Calendar** ⌘O      | Opens the day-view reminder window                                                  |
| **Testing** ▶             | Mock events, time scrubber, day picker, fallback toggle — see [Testing & debug](#testing--debug) |
| **Quit** ⌘Q               | Quits the app                                                                       |

All settings are saved in `UserDefaults` and take effect immediately (no restart required).

---

## Reminder window

Always on top, centred, and steals keyboard focus. **Esc** or the title-bar close button dismisses it. The window has **no fixed size** — both dimensions are derived from the day's events:

- **Width** scales with the visible time span (45 px per hour), so a busy day is wider than a quiet one.
- **Height** grows to fit every event (minimum 7 rows), never shrinking below a constant minimum set by the left column.

It is split into two columns.

### Left column (accent colour)

The whole column is tinted by urgency and recolours live as the countdown ticks:

| Next event is…   | Colour |
| ---------------- | ------ |
| > 2 minutes away | Blue   |
| ≤ 2 minutes away | Red    |
| none (all clear) | Grey   |

It holds two fixed-height slots:

- **Top — selected event** (empty until you click a timeline row): calendar name, event title (up to 2 lines), and `HH:mm – HH:mm · duration`.
- **Bottom — next event**: a `NEXT` label, the event title, and a large monospaced countdown with a blinking colon. When there is no upcoming event it reads **All clear**.

### Right column (white)

**Date header** — weekday and date (e.g. `Sunday, May 17`). Below it, one of two views:

#### Timeline (default)

A Gantt-style timeline, one row per event sorted by start time.

- **Time axis** — minimum **09:00 – 18:00**, extended to fit any events outside that band, snapped to whole hours, and capped at **03:00** the next morning. Hour gridlines with labels along the bottom.
- **"Now" marker** — a solid red vertical line with a dot and the current `HH:mm` at the top.
- **Event rows** — each draws a bold time badge, an L-shaped start marker + duration line, and the title:
  - starting **before 13:00** → title to the **right** of the badge;
  - starting **at/after 13:00** → title to the **left** of the start marker.
- Rows are **clickable** — click to show that event in the left column's top slot; click again to deselect (the selected event's title is drawn bold).

| Event state  | Colour        |
| ------------ | ------------- |
| Past (ended) | Grey (dimmed) |
| In progress  | Green         |
| Future       | Blue          |

#### Fallback list

When the timeline would be impractical — **more than 10 events**, or any event starting **before 08:00** or ending **after 20:00** — the right column switches to a plain scrolling list instead. Each row shows the start time, title, and a relative offset (`now`, `in 1h 5m`); past events are dimmed. It can also be forced from the Testing menu.

---

## Sound

Plays `/System/Library/Sounds/Glass.aiff` via `NSSound` when the reminder window appears.

---

## Testing & debug

The menu bar **Testing ▶** submenu drives a simulated environment for working on the UI without waiting for real meetings. Nothing here affects what you see unless **Test mode enabled** is on.

| Control               | What it does                                                              |
| --------------------- | ------------------------------------------------------------------------ |
| Test mode enabled     | Master switch — keeps every setting below intact when off                |
| Inject mock events    | Toggle individual fixed time-of-day sample events (e.g. `Standup 09:30`) |
| Hide real events      | Show only the mock events                                                 |
| Force fallback list   | Force the plain-list view regardless of event count/span                 |
| Choose day            | Shift the simulated day (last week … next week)                          |
| Simulate time         | A slider to scrub the clock across the whole day; **Real-time** resets it |
| Force check now       | Re-poll immediately                                                       |
| Clear shown reminders | Forget which reminders have fired so they can re-trigger                 |

Scrubbing the time slider refreshes any open calendar window **in place** (now-marker, colours, countdown). Toggling mock events, the day, or the fallback view recreates the open calendar window so the change shows immediately.

The same logic powers a browser prototype under `web/` (TypeScript + Vite), which is the design reference the Swift timeline mirrors.

---

## Project structure

```
calendar-blocker/
├── Package.swift                         — Swift package manifest (macOS 13+)
├── run.sh                                — build release + launch
├── watch.sh                              — hot-reload dev loop
├── .env                                  — local config (git-ignored)
└── Sources/CalendarBlocker/
    ├── main.swift                        — entry point; NSApplication setup
    ├── AppDelegate.swift                 — app lifecycle, polling timer, status bar wiring
    ├── CalendarChecker.swift             — iCal fetch/parse; upcoming + today events
    ├── ICalParser.swift                  — raw iCal text → Event structs
    ├── RRuleExpander.swift               — RFC 5545 RRULE → concrete occurrence dates
    ├── ReminderWindow.swift              — two-column NSWindow with Gantt timeline
    ├── StatusBarController.swift         — menu bar icon with live countdown
    └── Config.swift                      — UserDefaults-backed settings with save helpers
```

---

## Configuration reference

All settings are stored in `UserDefaults` and configured via the menu bar. No config files or environment variables needed.

| Setting           | Default          | Where to change               |
| ----------------- | ---------------- | ----------------------------- |
| iCal URLs         | — (one per line) | Menu bar → Set Calendar URLs… |
| Warning threshold | 10 min           | Menu bar → Remind me          |
| Sound             | On               | Menu bar → Sound              |

The poll interval is fixed at 60 s.
