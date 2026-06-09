import { DrawCtx, font, Font } from "./drawctx";
import { CalEvent, startsInSeconds, durationSeconds } from "./model";
import { pad2, hhmm, startOfDay, sameDay, setHour, addHours } from "./utils";

export const palette = {
  accentInProgress: "#dc2626", // red — urgent
  accentSoon: "#2563eb", // blue — default
  accentNone: "#475569", // gray — no next event

  systemBlue: "#007aff", // upcoming event
  systemGreen: "#34c759", // in-progress event
  systemRed: "#ff3b30", // now marker

  label: "#000000",
  secondaryLabel: "#3c3c4399",
  tertiaryLabel: "#3c3c434d",
  separator: "#3c3c434a",
  white: "#ffffff",
};

export const hoursYoffset = 20;



export const shapeStrokeW = 2;
export const shapeCornerR = 4;

// Left column padding (the HTML accent panel) — each side independent.
export const leftColPadT = 16;
export const leftColPadR = 16;
export const leftColPadB = 16;
export const leftColPadL = 16;

// Right column padding (date header + timeline canvas) — each side independent.
export const rightColPadT = 9;
export const rightColPadR = 4;
export const rightColPadB = 4;
export const rightColPadL = 4;

export const panelGap = 16;
export const dateHeaderH = 22;
export const dateHeaderGap = 6;
// Extra left indent of the date text, to align it with the timeline content.
export const dateHeaderIndent = 8;

export const maxTimelineTitleW = 150;
// Events at or after this hour get the title drawn left of the start marker.
export const titleLeftThresholdHour = 13;

export const leftPanelTitleFontSz = 15;
export const leftPanelMaxTitleLines = 2;

export const leftW = 210;
export const urgentThreshold = 120; // seconds

export const pxPerHour = 45;
export const pxPerMin = pxPerHour / 60;
export const defaultHourRange: [number, number] = [9, 18]; // minimum visible range

// Auto-fallback thresholds: the timeline gets impractical when events span too
// wide a day or there are too many of them — switch to the plain list instead.
export const fallbackEarliestHour = 8; // any event starting before this hour
export const fallbackLatestHour = 20; // any event ending after this hour
export const fallbackMaxEvents = 10; // more than this many events

export const axisPaddingStartMin = 0;
export const axisPaddingEndMin = 0;
export const snapToWholeHours = true;
export const timelinePadL = 10; // px
export const timelinePadR = 10; // px

export const timelineFontSize = 13;

// timeline height:
export const nowLabelH = 20;
export const firstEventPad = 8;
// event
export const eventsGap = 4;
export const badgeH = 16;
export const rowH = badgeH + eventsGap;
//
export const lastEventPad = 8;
export const hoursH = 12 + 19;

export const timelineMinHeight = timeLineHeight(7);

// Web approximation of AppKit line height (fontSize * 1.21).
export function lineHeight(size: number): number {
  return Math.ceil(size * 1.21);
}

const calLblLineH = lineHeight(10);
const infoLineH = lineHeight(11);
const nextLblLineH = lineHeight(9);
const timerLineH = lineHeight(52);
export const leftPanelTitleMaxH =
  lineHeight(leftPanelTitleFontSz) * leftPanelMaxTitleLines + 4;

// calLabel + 4 + title + 6 + info
export const selectedSlotH =
  calLblLineH + 4 + leftPanelTitleMaxH + 6 + infoLineH;
// nextLabel + title + 1 + timer
export const nextSlotH = nextLblLineH + leftPanelTitleMaxH + 1 + timerLineH;
export const winContentH =
  leftColPadT + selectedSlotH + panelGap + nextSlotH + leftColPadB;

export function durString(minutes: number): string {
  if (minutes <= 0) return "";
  const m = Math.min(minutes, 23 * 60 + 59);
  const h = Math.floor(m / 60);
  const rem = m % 60;
  if (h > 0) return rem > 0 ? `${h}h ${rem}m` : `${h}h`;
  return `${rem}m`;
}

// "H:MM" when >= 1h, "MM:SS" otherwise, "NOW" once started
export function countdownText(rawSecs: number): string {
  const secs = Math.max(0, rawSecs);
  if (secs <= 0) return "NOW";
  const totalMin = Math.floor(secs / 60);
  if (totalMin >= 60) {
    return `${Math.floor(totalMin / 60)}:${pad2(totalMin % 60)}`;
  }
  return `${pad2(totalMin)}:${pad2(Math.floor(secs % 60))}`;
}

export function accentColor(next: CalEvent | null, now: Date): string {
  if (!next) return palette.accentNone;
  return startsInSeconds(next, now) <= urgentThreshold
    ? palette.accentInProgress
    : palette.accentSoon;
}

export interface VisibleEvents {
  visible: CalEvent[];
  next: CalEvent | null;
}

export function computeVisible(
  all: CalEvent[],
  now: Date,
  triggering: CalEvent | null = null,
): VisibleEvents {
  const visible = all.filter((e) => sameDay(e.start, now));
  return {
    visible,
    next: triggering ?? visible.find((e) => e.end > now) ?? null,
  };
}

/// Whether the timeline should be replaced by the plain list: too many events,
/// or any event reaching outside the [earliest, latest] hour band of the day.
export function shouldUseFallback(events: CalEvent[], now: Date): boolean {
  if (events.length > fallbackMaxEvents) return true;
  const dayStart = startOfDay(now);
  const earliest = addHours(dayStart, fallbackEarliestHour);
  const latest = addHours(dayStart, fallbackLatestHour);
  return events.some((e) => e.start < earliest || e.end > latest);
}

export interface TimeMap {
  rs: Date;
  re: Date;
  t2x: (t: Date) => number;
}

export function timeMap(events: CalEvent[], now: Date): TimeMap {
  let rs = setHour(now, defaultHourRange[0]);
  let re = setHour(now, defaultHourRange[1]);

  if (events.length > 0) {
    const earliest = new Date(
      events[0].start.getTime() - axisPaddingStartMin * 60_000,
    );
    const latest = new Date(
      events[events.length - 1].end.getTime() + axisPaddingEndMin * 60_000,
    );
    rs = new Date(Math.min(rs.getTime(), earliest.getTime()));
    re = new Date(Math.max(re.getTime(), latest.getTime()));
  }

  if (snapToWholeHours) {
    const dayMs = startOfDay(now).getTime();
    rs = setHour(now, Math.floor((rs.getTime() - dayMs) / 3_600_000));
    re = setHour(now, Math.ceil((re.getTime() - dayMs) / 3_600_000));
  }

  // cap at 03:00 next day
  re = new Date(
    Math.min(re.getTime(), addHours(startOfDay(now), 27).getTime()),
  );

  const t2x = (t: Date) =>
    timelinePadL + ((t.getTime() - rs.getTime()) / 60_000) * pxPerMin;

  return { rs, re, t2x };
}

export interface TimelineLayout {
  // height components (sum to total height)
  nowLabelH: number;
  firstEventPad: number;
  eventsH: number;
  eventsGap: number;
  lastEventPad: number;
  hoursH: number;
  // width components (sum to total width)
  padL: number;
  eventsSpanW: number;
  padR: number;
  // derived totals
  width: number;
  height: number;
  // time mapping
  rs: Date;
  re: Date;
  t2x: (t: Date) => number;
}

export function timeLineHeight(evCnt: number) {
  const evH = evCnt * rowH;

  return nowLabelH + firstEventPad + evH + lastEventPad + hoursH;
}

export function computeTimelineLayout(
  events: CalEvent[],
  now: Date,
): TimelineLayout {
  const { rs, re, t2x } = timeMap(events, now);
  const minutes = (re.getTime() - rs.getTime()) / 60_000;

  const evH = events.length * rowH;
  const padL = timelinePadL;
  const eventsSpanW = minutes * pxPerMin;
  const padR = timelinePadR;

  const height = Math.max(timelineMinHeight, timeLineHeight(events.length));
  console.log({height});
  const width = padL + eventsSpanW + padR;

  return {
    nowLabelH,
    firstEventPad,
    eventsH: evH,
    eventsGap,
    lastEventPad,
    hoursH,
    padL,
    eventsSpanW,
    padR,
    width,
    height,
    rs,
    re,
    t2x,
  };
}

export function windowWidth(tlWidth: number): number {
  return leftW + rightColPadL + rightColPadR + tlWidth;
}

export function hourGridlines(rs: Date, re: Date): Date[] {
  const count = Math.floor((re.getTime() - rs.getTime()) / 3_600_000) + 1;
  return Array(count)
    .fill(0)
    .map((_, i) => addHours(rs, i));
}

export function rowAt(y: number, count: number): number | null {
  const row = Math.floor((y - hoursYoffset) / rowH);
  if (row < 0 || row >= count) return null;
  return row;
}

export { startsInSeconds, durationSeconds };

// --- Renderer ---

export interface TimelineProps {
  events: CalEvent[];
  focused: CalEvent | null;
  now: Date;
  layout: TimelineLayout;
}

function truncate(ctx: DrawCtx, text: string, f: Font, maxW: number): string {
  if (ctx.measureText(text, f).width <= maxW) return text;
  let lo = 0;
  let hi = text.length;
  while (lo < hi) {
    const mid = Math.ceil((lo + hi) / 2);
    if (ctx.measureText(text.slice(0, mid) + "…", f).width <= maxW) lo = mid;
    else hi = mid - 1;
  }
  return lo > 0 ? text.slice(0, lo) + "…" : "";
}

export function renderTimeline(ctx: DrawCtx, p: TimelineProps): void {
  const { events, now, layout } = p;
  if (events.length === 0) return;

  const { rs, re, t2x, nowLabelH, firstEventPad, hoursH } = layout;
  const eventsTop = nowLabelH + firstEventPad;
  const bottomY = layout.height - hoursH;

  // Hour gridlines + axis labels
  const lblFont = font(timelineFontSize - 2, "medium", true);
  for (const cur of hourGridlines(rs, re)) {
    const x = t2x(cur);

    ctx.stroke(
      ctx.beginPath().moveTo(x, nowLabelH).lineTo(x, bottomY),
      palette.separator,
      0.5,
    );

    const lbl = String(cur.getHours());
    const sz = ctx.measureText(lbl, lblFont);
    ctx.fillText(
      lbl,
      x - sz.width / 2,
      bottomY + (nowLabelH - sz.height) / 2,
      lblFont,
      palette.secondaryLabel,
    );
  }

  // "Now" marker
  if (now >= rs && now <= re) {
    const nx = t2x(now);
    const dotR = 3;
    ctx.stroke(
      ctx
        .beginPath()
        .moveTo(nx, nowLabelH / 2)
        .lineTo(nx, bottomY),
      palette.systemRed,
      1,
      0.5,
    );
    ctx.fill(
      ctx.beginPath().arc(nx, nowLabelH / 2, dotR, 0, 360, true),
      palette.systemRed,
    );
    const nowFont = font(timelineFontSize - 2, "semibold", true);
    const nowStr = hhmm(now);
    const nsz = ctx.measureText(nowStr, nowFont);
    ctx.fillText(
      nowStr,
      nx + dotR + 3,
      (nowLabelH - nsz.height) / 2,
      nowFont,
      palette.systemRed,
    );
  }

  interface EvLayout {
    cy: number;
    x1: number;
    x2: number;
    color: string;
    alpha: number;
    timeStr: string;
    timeFont: Font;
    timeOrigin: { x: number; y: number };
    timeSz: { width: number; height: number };
    titleStr: string;
    titleFont: Font;
    titleColor: string;
    titleRect: { x: number; y: number; w: number; h: number };
  }

  const layouts: EvLayout[] = [];
  events.forEach((ev, i) => {
    const cy = eventsTop + i * rowH + rowH / 2;
    const x1 = t2x(ev.start);
    const x2 = t2x(ev.end);
    const done = ev.end <= now;
    const isFocused =
      p.focused != null &&
      p.focused.start.getTime() === ev.start.getTime() &&
      p.focused.title === ev.title;

    let color: string;
    if (done) color = palette.tertiaryLabel;
    else if (ev.start <= now && now < ev.end) color = palette.systemGreen;
    else color = palette.systemBlue;
    const alpha = done ? 0.35 : 1;

    const timeFont = font(timelineFontSize, "bold");
    const timeStr = hhmm(ev.start);
    const timeSz = ctx.measureText(timeStr, timeFont);
    const timeOrigin = {
      x: x1 + shapeStrokeW / 2 + 2,
      y: cy - timeSz.height / 2,
    };

    const titleColor = done ? palette.tertiaryLabel : palette.label;
    const titleFont = font(timelineFontSize, isFocused ? "bold" : "regular");
    const isTitleOnLeft = ev.start.getHours() >= titleLeftThresholdHour;
    const afterTimeX = x1 + shapeStrokeW / 2 + 4 + timeSz.width + 6;
    const natural = ctx.measureText(ev.title, titleFont);
    const titleH = natural.height;

    let titleRect: { x: number; y: number; w: number; h: number };
    if (isTitleOnLeft) {
      const maxW = Math.min(
        maxTimelineTitleW,
        Math.max(0, x1 - 6 - timelinePadL),
      );
      const drawW = Math.min(natural.width, maxW);
      titleRect = {
        x: x1 - 6 - drawW,
        y: cy - titleH / 2,
        w: drawW,
        h: titleH,
      };
    } else {
      const drawW = Math.min(natural.width, maxTimelineTitleW);
      titleRect = { x: afterTimeX, y: cy - titleH / 2, w: drawW, h: titleH };
    }

    layouts.push({
      cy,
      x1,
      x2,
      color,
      alpha,
      timeStr,
      timeFont,
      timeOrigin,
      timeSz,
      titleStr: ev.title,
      titleFont,
      titleColor,
      titleRect,
    });
  });

  // Pass 1: white backgrounds behind text
  for (const l of layouts) {
    ctx.fillRect(
      l.timeOrigin.x - 2,
      l.timeOrigin.y,
      l.timeSz.width + 4,
      l.timeSz.height,
      palette.white,
    );
    ctx.fillRect(
      l.titleRect.x - 2,
      l.titleRect.y,
      l.titleRect.w + 4,
      l.titleRect.h,
      palette.white,
    );
  }

  // Pass 2: L-shapes
  for (const l of layouts) {
    const bh2 = badgeH / 2;
    const r = Math.min(shapeCornerR, bh2);
    const ox = -1;
    const oy = 1;
    const x1 = l.x1 + ox;
    const botY = l.cy + bh2 + oy;
    const path = ctx
      .beginPath()
      .moveTo(x1, l.cy - bh2 + oy)
      .lineTo(x1, botY - r)
      .arc(x1 + r, botY - r, r, 180, 90, false)
      .lineTo(l.x2 + ox, botY);
    ctx.stroke(path, l.color, shapeStrokeW, l.alpha, "round");
  }

  // Pass 3: text
  for (const l of layouts) {
    ctx.fillText(
      l.timeStr,
      l.timeOrigin.x,
      l.timeOrigin.y,
      l.timeFont,
      l.color,
      l.alpha,
    );
    const shown = truncate(ctx, l.titleStr, l.titleFont, l.titleRect.w);
    ctx.fillText(
      shown,
      l.titleRect.x,
      l.titleRect.y,
      l.titleFont,
      l.titleColor,
    );
  }
}
