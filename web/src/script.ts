// Orchestrator: builds the reminder-window mock, wires the pure-HTML devtools,
// and drives the calendar render loop. Calendar rendering itself lives in the
// transpilable modules (layout / timeline / leftColumn); this file is web glue.

import { CalEvent, buildMockEvents, mockEventDefs } from './model'
import {
  computeVisible, rowAt, winW, winContentH, leftW, leftColPad, winVPad,
  rightColPad, dateHeaderTop, dateHeaderH, dateHeaderGap, timelineW, timelineH,
} from './layout'
import { CanvasDrawCtx } from './canvas'
import { renderTimeline } from './timeline'
import { renderLeftColumn } from './leftColumn'

// MARK: - Debug log
const debugLog = {
  log(message: string, type: 'info' | 'error' | 'success' = 'info') {
    const logEl = document.getElementById('debug-log')
    if (!logEl) return
    const entry = document.createElement('div')
    entry.className = `dev-log-entry ${type}`
    entry.textContent = `[${new Date().toLocaleTimeString()}] ${message}`
    logEl.appendChild(entry)
    logEl.scrollTop = logEl.scrollHeight
    while (logEl.children.length > 20) logEl.removeChild(logEl.firstChild!)
  },
}

// MARK: - State
const DEFAULT_ENABLED = ['inprogress', 'soon', 'upcoming', 'overlap1', 'later', 'very_long']

const state = {
  enabled: new Set<string>(DEFAULT_ENABLED),
  offsetMin: 0,
  events: [] as CalEvent[],
  now0: new Date(),    // simulated time when events were last built
  realStart: 0,        // performance baseline for advancing the clock
  selected: null as CalEvent | null,
}

let ctx: CanvasDrawCtx
let leftEl: HTMLElement
let dateEl: HTMLElement
let canvasEl: HTMLCanvasElement

const dateFmt = new Intl.DateTimeFormat(undefined, { weekday: 'long', month: 'short', day: 'numeric' })

function displayNow(): Date {
  return new Date(state.now0.getTime() + (Date.now() - state.realStart))
}

/// Rebuilds mock events against a fresh simulated `now0`. Call on offset/toggle change.
function rebuild() {
  state.now0 = new Date(Date.now() + state.offsetMin * 60_000)
  state.realStart = Date.now()
  state.events = buildMockEvents(state.enabled, state.now0)
  state.selected = null
  render()
}

function render() {
  const now = displayNow()
  const vis = computeVisible(state.events, now)

  dateEl.textContent = dateFmt.format(now)
  renderLeftColumn(leftEl, { selected: state.selected, next: vis.next, now })

  ctx.clear()
  renderTimeline(ctx, {
    events: vis.visible,
    hiddenPast: vis.hiddenPast,
    hiddenFuture: vis.hiddenFuture,
    focused: state.selected,
    now,
    width: timelineW,
    height: timelineH,
  })
}

// MARK: - Window dimensions (single source of truth = layout.ts)
function applyDimensions() {
  const win = document.getElementById('window')!
  win.style.width = `${winW}px`
  win.style.height = `${winContentH}px`

  leftEl.style.width = `${leftW}px`
  leftEl.style.padding = `${winVPad}px ${leftColPad}px`

  dateEl.style.margin = `${dateHeaderTop}px 0 ${dateHeaderGap}px ${rightColPad + 8}px`
  dateEl.style.height = `${dateHeaderH}px`
  dateEl.style.fontSize = `15px`

  canvasEl.style.width = `${timelineW}px`
  canvasEl.style.height = `${timelineH}px`
  canvasEl.style.marginLeft = `${rightColPad}px`
}

// MARK: - Dev tools
function buildMockControls() {
  const host = document.getElementById('mock-events')!
  for (const def of mockEventDefs) {
    const row = document.createElement('div')
    row.className = 'mock-row'
    const cb = document.createElement('input')
    cb.type = 'checkbox'
    cb.id = `mock-${def.id}`
    cb.checked = state.enabled.has(def.id)
    cb.addEventListener('change', () => {
      if (cb.checked) state.enabled.add(def.id)
      else state.enabled.delete(def.id)
      debugLog.log(`${cb.checked ? 'enabled' : 'disabled'} "${def.id}"`)
      rebuild()
    })
    const label = document.createElement('label')
    label.htmlFor = cb.id
    label.textContent = `${def.id} (${def.offsetMinutes >= 0 ? '+' : ''}${def.offsetMinutes}m)`
    row.append(cb, label)
    host.appendChild(row)
  }
}

function wireTimeControls() {
  const range = document.getElementById('time-range') as HTMLInputElement
  const num = document.getElementById('time-offset') as HTMLInputElement
  const apply = (v: number) => {
    state.offsetMin = v
    range.value = String(v)
    num.value = String(v)
    rebuild()
  }
  range.addEventListener('input', () => apply(Number(range.value)))
  num.addEventListener('change', () => apply(Number(num.value)))

  document.getElementById('reset-btn')!.addEventListener('click', () => {
    state.enabled = new Set(DEFAULT_ENABLED)
    for (const def of mockEventDefs) {
      ;(document.getElementById(`mock-${def.id}`) as HTMLInputElement).checked = state.enabled.has(def.id)
    }
    apply(0)
    debugLog.log('reset', 'info')
  })
}

function wireCanvasSelection() {
  canvasEl.addEventListener('click', (e) => {
    const rect = canvasEl.getBoundingClientRect()
    const y = e.clientY - rect.top
    const now = displayNow()
    const vis = computeVisible(state.events, now)
    const row = rowAt(y, vis.rowOffset, vis.visible.length)
    if (row == null) return
    const ev = vis.visible[row]
    state.selected = state.selected === ev ? null : ev // toggle
    render()
  })
}

// MARK: - Init
function init() {
  leftEl = document.getElementById('left-column')!
  dateEl = document.getElementById('date-header')!
  canvasEl = document.getElementById('timeline') as HTMLCanvasElement

  applyDimensions()
  ctx = new CanvasDrawCtx(canvasEl)

  buildMockControls()
  wireTimeControls()
  wireCanvasSelection()

  rebuild()
  setInterval(render, 1000) // advance countdown + now marker
  debugLog.log('App initialized', 'success')
}

document.addEventListener('DOMContentLoaded', init)
