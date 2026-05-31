// Renderer — a near-1:1 port of TimelineView.draw (ReminderWindow.swift).
// Talks only to DrawCtx, so the same logic backs Canvas2D here and NSBezierPath
// in Swift. Measurement (measureText) lives here, exactly as draw() uses
// size(withAttributes:).

import { DrawCtx, font, Font } from "./drawctx";
import { CalEvent } from "./model";
import {
  axisH,
  badgeH,
  timelinePadL,
  timelinePadR,
  rowH,
  shapeCornerR,
  shapeStrokeW,
  timelineFontSize,
  maxTimelineTitleW,
  titleLeftThresholdHour,
  palette,
  hhmm,
  timeMap,
  hourGridlines,
} from "./layout";

export interface TimelineProps {
  events: CalEvent[]; // all of today's events, in order
  focused: CalEvent | null;
  now: Date;
  width: number;
  height: number;
}

/// Truncate-tail to fit `maxW`, appending an ellipsis — replaces NSLineBreakMode.byTruncatingTail.
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
  const { events, now, width: w, height } = p;
  if (events.length === 0) return;

  const { rs, re, t2x } = timeMap(events, now);
  const bottomY = height - axisH - 18; // top of bottom label band

  // Hour gridlines + axis labels (labels at bottom)
  const lblFont = font(timelineFontSize - 2, "medium", true);
  for (const cur of hourGridlines(rs, re)) {
    const x = t2x(cur);
    ctx.stroke(
      ctx.beginPath().moveTo(x, axisH).lineTo(x, bottomY),
      palette.separator,
      0.5,
    );

    const lbl = String(cur.getHours());
    const sz = ctx.measureText(lbl, lblFont);
    ctx.fillText(
      lbl,
      x - sz.width / 2,
      bottomY + (axisH - sz.height) / 2,
      lblFont,
      palette.secondaryLabel,
    );
  }

  // "Now" marker — line through rows, dot + time label at top
  if (now >= rs && now <= re) {
    const nx = t2x(now);
    const dotR = 3;
    ctx.stroke(
      ctx
        .beginPath()
        .moveTo(nx, axisH / 2)
        .lineTo(nx, bottomY),
      palette.systemRed,
      1,
      0.5,
    );
    ctx.fill(
      ctx.beginPath().arc(nx, axisH / 2, dotR, 0, 360, true),
      palette.systemRed,
    );

    const nowFont = font(timelineFontSize - 2, "semibold", true);
    const nowStr = hhmm(now);
    const nsz = ctx.measureText(nowStr, nowFont);
    ctx.fillText(
      nowStr,
      nx + dotR + 3,
      (axisH - nsz.height) / 2,
      nowFont,
      palette.systemRed,
    );
  }

  // Precompute per-event layout (matches the EvLayout pass in Swift).
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
    const cy = axisH + i * rowH + rowH / 2;
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
    const isAfternoon = ev.start.getHours() >= titleLeftThresholdHour;
    const afterTimeX = x1 + shapeStrokeW / 2 + 4 + timeSz.width + 6;

    const natural = ctx.measureText(ev.title, titleFont);
    const titleH = natural.height;

    let titleRect: { x: number; y: number; w: number; h: number };
    if (isAfternoon) {
      const maxW = Math.min(maxTimelineTitleW, Math.max(0, x1 - 6 - timelinePadL));
      const drawW = Math.min(natural.width, maxW);
      titleRect = {
        x: x1 - 6 - drawW,
        y: cy - titleH / 2,
        w: drawW,
        h: titleH,
      };
    } else {
      const maxW = Math.max(0, w - timelinePadR - afterTimeX);
      const drawW = Math.min(natural.width, maxW);
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

  // Pass 1: white backgrounds behind text (sized to rendered width, inset -2).
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

  // Pass 2: L-shapes on top of the white backgrounds.
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

  // Pass 3: text on top.
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
