# Calendar Blocker - Web UI Prototype

A lightweight, playground environment for rapid UI prototyping using Vite and TypeScript (type-stripping only).

## Setup

```bash
cd web
npm install
npm run dev
```

## Project Structure

- `index.html` - Main HTML file with all styles embedded
- `src/script.ts` - Main TypeScript entry point (type-stripping only, no bundling)
- `vite.config.ts` - Minimal Vite configuration
- Dev tools sidebar - Quick controls and debug logging

## Canvas vs SVG?

**Canvas:**
- Better for high-performance rendering (games, animations, dense visualizations)
- Pixel-based, requires manual drawing commands
- Harder to make accessible
- Good for: smooth animations, high frame rate interactions

**SVG:**
- Better for scalable, semantic graphics
- Vector-based, resolution-independent
- Can interact with DOM, easier accessibility
- Good for: diagrams, charts, interactive shapes

**Recommendation for calendar UI:** SVG is likely better since calendars need precision, interactivity, and accessibility. Canvas is good if you want smooth drag/animation effects.

## Dev Tools

The right sidebar provides:
- Toggle between Canvas/SVG rendering
- Clear/Reset buttons
- Debug log with timestamps

## Notes

- This is a playground—no linters, formatters, or build complexity
- All styles are in `index.html` inside `<style>` tags
- Modify freely for rapid iteration!
