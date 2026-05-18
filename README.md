# Calendar Blocker

A native macOS app (Swift + AppKit) that shows an aggressive reminder window when a Google Calendar event is about to start. No OAuth, no Google API SDK — just a private iCal feed URL. Includes a menu bar icon with a live countdown to your next event.

---

## How it works

1. A background timer polls your Google Calendar iCal feed every 30 seconds.
2. When an event falls within the warning window (default 10 min before start), a reminder window appears on top of all other windows and steals focus.
3. The same event is never shown twice in the same session (dedup by title + start time).
4. Events that started up to a few minutes ago are still shown if a poll cycle missed them.
5. Recurring events (RRULE) are fully expanded — daily, weekly, monthly, and yearly patterns are supported.
6. A menu bar icon shows the next event title and an animated live countdown; clicking it opens a menu with a link to Google Calendar and a Quit option.

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

Run the app and click the calendar icon in the menu bar → **Set Calendar URL…** Paste your iCal URL and press **Save**. The URL is stored in `UserDefaults` and persists across launches.

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

The status bar item shows a calendar SF Symbol and a live countdown label that updates every 30 seconds (between polls).

| State | Symbol | Colour |
|---|---|---|
| Event in progress or just started | `calendar.badge.clock` | Red |
| < 5 min away | `calendar.badge.clock` | Orange |
| Further away | `calendar` | Secondary grey |
| No events today | `calendar` | Secondary grey, no label |

Clicking the icon shows a dropdown:

| Item | Action |
|---|---|
| Event title · start time | Read-only, shows the next upcoming event |
| **Set Calendar URL…** ⌘, | Opens an input dialog to paste your iCal URL |
| **Check every** ▶ | Submenu: 15 s / 30 s / 1 min / 5 min |
| **Remind me** ▶ | Submenu: 5 / 10 / 15 / 30 minutes before |
| **Sound** ✓ | Toggle the Glass sound on reminder |
| **Open Calendar** ⌘O | Opens the day-view reminder window |
| **Quit** ⌘Q | Quits the app |

All settings are saved in `UserDefaults` and take effect immediately (no restart required).

---

## Reminder window

The window is 720 × (dynamic height) px, always on top, steals keyboard focus.  
It is split into two columns separated by a 1 px hairline.

### Left column (white)

| Element | Detail |
|---|---|
| Urgency badge | Coloured pill: amber / orange / red depending on time to start |
| Animated timer | Live countdown (updates every second) showing time until event starts |
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
- Rows are **clickable** — clicking a row selects that event and shows its details in the left column. Clicking the same row again deselects it.

#### Event state colours

| State | Colour |
|---|---|
| Done (ended) | Grey |
| Active (in progress) | Green |
| **Selected / focused** | Accent colour |
| Overlapping | Orange |
| Upcoming | Blue |

#### Selected event detail (left column)

When a timeline row is clicked, the top of the left column shows:

| Element | Detail |
|---|---|
| Event title | Bold white, wraps to multiple lines |
| Time range | `HH:mm – HH:mm` |
| Duration | e.g. `1h 30m` |
| Open in Calendar → | Opens the event in Google Calendar (day view for that date) |

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

| Setting | Default | Where to change |
|---|---|---|
| iCal URL | — | Menu bar → Set Calendar URL… |
| Poll interval | 30 s | Menu bar → Check every |
| Warning threshold | 10 min | Menu bar → Remind me |
| Sound | On | Menu bar → Sound |
