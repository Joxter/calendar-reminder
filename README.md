# Calendar Blocker

A native macOS app (Swift + AppKit) that shows an aggressive reminder window when a Google Calendar event is about to start. No OAuth, no Google API SDK — just a private iCal feed URL.

---

## How it works

1. A background timer polls your Google Calendar iCal feed every 30 seconds.
2. When an event falls within the warning window (default 10 min before start), a reminder window appears on top of all other windows and steals focus.
3. The same event is never shown twice in the same session (dedup by title + start time).
4. Events that started up to a few minutes ago are still shown if a poll cycle missed them.

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

Create a `.env` file in the repo root:

```bash
ICAL_URL=https://calendar.google.com/calendar/ical/you%40gmail.com/private-XXXXX/basic.ics
```

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

## Reminder window

The window is 720 × (dynamic height) px, always on top, steals keyboard focus.  
It is split into two columns separated by a 1 px hairline.

### Left column (white)

| Element | Detail |
|---|---|
| Urgency badge | Coloured pill: amber / orange / red depending on time to start |
| Event title | SF Pro Display bold, wraps to multiple lines |
| Duration | `h:mm` format (e.g. `0:30`, `1:00`) |
| Dismiss button | Accent colour; hover darkens. Also responds to **Esc**, **Return**, and window close. |

### Right column (`#f5f5f7`)

**Date header** — weekday and date (e.g. `Sunday, May 17`).

**Timeline canvas** — Gantt-style, one row per event sorted by start time.

#### Time axis

- Fixed range **08:00 – 18:00** local time, extended automatically if any event falls outside.
- Hour labels in light grey, vertical gridlines at each hour.
- **"Now" marker** — dashed vertical line in light pink.

#### Event rows

Each event renders a time badge, a duration underline, and a title with duration label.

- Events starting **before 13:00**: title appears to the **right** of the badge.
- Events starting **at or after 13:00**: title appears to the **left** to avoid clipping.

#### Event state colours

| State | Colour |
|---|---|
| Done (ended) | Grey |
| Active (in progress) | Green |
| **Focused** (this reminder) | Accent colour |
| Overlapping | Orange |
| Upcoming | Blue |

---

## Sound

Plays `/System/Library/Sounds/Glass.aiff` via `NSSound` when the reminder window appears.

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
    ├── AppDelegate.swift                 — app lifecycle, polling timer
    ├── CalendarChecker.swift             — iCal fetch/parse; upcoming + today events
    ├── ICalParser.swift                  — raw iCal text → Event structs
    ├── ReminderWindow.swift              — two-column NSWindow with Gantt timeline
    └── Config.swift                      — reads ICAL_URL from env / .env file
```

---

## Configuration reference

| Variable | Default | Description |
|---|---|---|
| `ICAL_URL` | — | Private iCal feed URL (required) |
| `pollInterval` | `30` s | Seconds between calendar fetches (in `Config.swift`) |
| `warningThreshold` | `600` s | Seconds before event start to trigger reminder (in `Config.swift`) |
