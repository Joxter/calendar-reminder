# Calendar Blocker - Web UI Prototype

A lightweight playground for rapid iteration on the reminder-window UI, built with
Vite + TypeScript (type-stripping only, no bundling). UI experiments here are
meant to be ported back to the Swift app (`Sources/CalendarBlocker/`).

## Setup

```bash
cd web
npm install
npm run dev
```

## Rendering approach: Canvas (not SVG)

The Swift timeline (`TimelineView.draw`) is **immediate-mode**: an ordered list of
`NSBezierPath` / `NSString.draw` commands. Canvas 2D is the same paradigm, so the
rendering code ports back to Swift by near-mechanical substitution. SVG is
retained-mode (a DOM tree) and would have to be rewritten for AppKit, so it is not
used here. (Devtools are plain HTML inputs, separate from the calendar render —
inspectability of the canvas was not a deciding factor.)

The real win is not the API choice but the structure:

- **Pure layout math** stays framework-free, so it transpiles verbatim.
- A thin **`DrawCtx` seam** sits between layout and pixels: Canvas2D backs it on
  the web; the Swift port backs it with `NSBezierPath` / `NSString.draw`.

## Module map (port targets in parentheses)

| File | Role | Swift counterpart |
|------|------|-------------------|
| `src/model.ts` | `CalEvent` + mock event defs | `ICalParser.swift`, `Config.mockEventDefs` |
| `src/layout.ts` | **Pure** constants, sizing, trimming, time→x, formatters | top of `ReminderWindow.swift` |
| `src/drawctx.ts` | `DrawCtx` / `Path` interface (the seam) | `NSBezierPath` / `NSString.draw` |
| `src/canvas.ts` | Canvas2D-backed `DrawCtx` | *(web only)* |
| `src/timeline.ts` | `renderTimeline` — 1:1 port of `draw()` | `TimelineView.draw` |
| `src/leftColumn.ts` | Left column as HTML/CSS | `buildLeftSlots` / `build*Content` |
| `src/script.ts` | Devtools wiring + render loop | *(web only)* |

When porting: `layout.ts` and `timeline.ts` are the files that map to Swift.
`canvas.ts` and `script.ts` are web-only glue and have no Swift counterpart.

## Dev tools

The right sidebar (pure HTML inputs) lets you:

- Toggle individual mock events (mirrors `Config.mockEventDefs`).
- Scrub simulated time (offset in minutes) — countdown and now-marker advance live.
- Reset to defaults.
- Read a timestamped debug log.

Click a timeline event to select it (fills the top-left slot); click again to deselect.

## Notes

- Playground rules: no linters/formatters, styles live in `index.html`.
- Font metrics are approximated as `size * 1.21` in `layout.ts` (AppKit uses real
  metrics) — this is the main prototype tuning knob if heights drift.
