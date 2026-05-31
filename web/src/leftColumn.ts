// Left column — the AppKit Auto-Layout part of ReminderWindow, rendered as
// plain HTML/CSS (no canvas). Mirrors buildLeftSlots / buildNextContent /
// buildSelectedContent / buildAllClear. Styling lives in index.html.

import { CalEvent } from './model'
import { accentColor, countdownText, durString, startsInSeconds, durationSeconds } from './layout';
import { hhmm } from './utils';

export interface LeftColumnProps {
  selected: CalEvent | null // top slot — filled on timeline click
  next: CalEvent | null     // bottom slot — drives countdown + accent
  now: Date
}

function el(tag: string, className: string, text?: string): HTMLElement {
  const e = document.createElement(tag)
  e.className = className
  if (text !== undefined) e.textContent = text
  return e
}

/// Top slot: calendar name, title (2 lines), "time · duration".
function selectedSlot(ev: CalEvent | null): HTMLElement {
  const slot = el('div', 'slot slot-selected')
  if (!ev) return slot // reserved empty space, matching the constant window height

  if (ev.calendarName) slot.appendChild(el('div', 'cal-name', ev.calendarName))
  slot.appendChild(el('div', 'slot-title', ev.title))

  const time = `${hhmm(ev.start)} – ${hhmm(ev.end)}`
  const dur = durString(Math.floor(durationSeconds(ev) / 60))
  slot.appendChild(el('div', 'slot-info', dur ? `${time}  ·  ${dur}` : time))
  return slot
}

/// Bottom slot: "NEXT" label, title (2 lines), big countdown — or "All clear".
function nextSlot(ev: CalEvent | null, now: Date): HTMLElement {
  const slot = el('div', 'slot slot-next')
  if (!ev) {
    slot.appendChild(el('div', 'all-clear', 'All clear'))
    return slot
  }
  slot.appendChild(el('div', 'next-label', 'NEXT'))
  slot.appendChild(el('div', 'slot-title', ev.title))

  const timer = el('div', 'countdown')
  // Blinking colon, like ReminderWindow.tick().
  timer.innerHTML = countdownText(startsInSeconds(ev, now)).replace(':', '<span class="colon">:</span>')
  slot.appendChild(timer)
  return slot
}

export function renderLeftColumn(container: HTMLElement, p: LeftColumnProps): void {
  container.style.backgroundColor = accentColor(p.next, p.now)
  container.replaceChildren(selectedSlot(p.selected), nextSlot(p.next, p.now))
}
