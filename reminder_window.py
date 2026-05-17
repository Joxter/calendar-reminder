from __future__ import annotations

import math
import subprocess
import tkinter as tk
from datetime import datetime, timezone, timedelta
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from calendar_checker import Event

_LEFT_BG = "#ffffff"
_RIGHT_BG = "#f5f5f7"
_PRI    = "#1d1d1f"
_SEC    = "#86868b"
_DIM    = "#c7c7cc"
_SEP    = "#e5e5ea"
_GREEN  = "#34c759"
_ORANGE = "#ff9f0a"
_BLUE   = "#007aff"
_RED    = "#ff3b30"

_AXIS_H   = 20   # px — hour-label row height
_ROW_H    = 22   # px — height per event row
_BADGE_W  = 40   # px — time badge width  (fits "HH:MM" at 11 pt)
_BADGE_H  = 16   # px — time badge height
_BADGE_R  = 3    # px — badge corner radius (BR stays square)
_LINE_H   = 2    # px — duration underline height
_L_PAD    = 10   # px — left padding inside timeline canvas
_R_PAD    = 10   # px — right padding
_FONT_SZ  = 11   # pt — unified font size for badge time, title, duration


def _play_sound() -> None:
    try:
        subprocess.Popen(["afplay", "/System/Library/Sounds/Glass.aiff"],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except FileNotFoundError:
        pass


def _urgency(event: "Event") -> tuple[str, str]:
    secs = event.starts_in_seconds
    if secs <= 0:
        return "IN PROGRESS", "#ef4444"
    if secs <= 120:
        m, s = int(secs) // 60, int(secs) % 60
        return f"STARTING IN {m}m {s}s", "#f97316"
    return f"STARTING IN {int(secs) // 60} MIN", "#f59e0b"


def _darken(c: str, f: float = 0.82) -> str:
    r, g, b = int(c[1:3], 16), int(c[3:5], 16), int(c[5:7], 16)
    return f"#{int(r*f):02x}{int(g*f):02x}{int(b*f):02x}"


def _lighten(c: str, f: float = 0.35) -> str:
    """Blend color *c* toward the right-column background (#f5f5f7) at factor f."""
    r, g, b = int(c[1:3], 16), int(c[3:5], 16), int(c[5:7], 16)
    return (f"#{int(r*f + 0xf5*(1-f)):02x}"
            f"{int(g*f + 0xf5*(1-f)):02x}"
            f"{int(b*f + 0xf7*(1-f)):02x}")


def _dur_str(event: "Event") -> str:
    m = int((event.end - event.start).total_seconds() / 60)
    if m <= 0: return ""
    return f"{m // 60}:{m % 60:02d}"


def _label_btn(parent: tk.Widget, text: str, bg: str, cmd) -> tk.Label:
    hover = _darken(bg)
    btn = tk.Label(parent, text=text, font=("SF Pro Text", 12, "bold"),
                   fg="#ffffff", bg=bg, padx=16, pady=7, cursor="hand2")
    btn.bind("<Button-1>", lambda _: cmd())
    btn.bind("<Enter>",    lambda _: btn.configure(bg=hover))
    btn.bind("<Leave>",    lambda _: btn.configure(bg=bg))
    return btn


def _overlapping_indices(events: list["Event"]) -> set[int]:
    result: set[int] = set()
    for i in range(len(events)):
        for j in range(i + 1, len(events)):
            a, b = events[i], events[j]
            if a.start < b.end and b.start < a.end:
                result.add(i)
                result.add(j)
    return result


def _draw_badge(
    canvas: tk.Canvas,
    x1: float, y1: float, x2: float, y2: float,
    r: int, fill: str,
) -> None:
    """Filled badge: TL, TR, BL corners rounded; BR stays square (where underline connects)."""
    pts: list[float] = []
    N = 6  # arc steps per quarter

    def _arc(cx: float, cy: float, a0: float, a1: float) -> None:
        for i in range(N + 1):
            a = math.radians(a0 + (a1 - a0) * i / N)
            pts.append(cx + r * math.cos(a))
            pts.append(cy - r * math.sin(a))   # screen-y inverted

    _arc(x1 + r, y1 + r,  90, 180)   # top-left
    pts += [x1,  y2 - r]              # left edge down to BL arc
    _arc(x1 + r, y2 - r, 180, 270)   # bottom-left
    pts += [x2,  y2]                  # bottom-right: SQUARE
    pts += [x2,  y1 + r]              # right edge up to TR arc
    _arc(x2 - r, y1 + r,   0,  90)   # top-right

    canvas.create_polygon(pts, fill=fill, outline="", smooth=False)


def _draw_timeline(
    canvas: tk.Canvas,
    today_events: list["Event"],
    focused: "Event",
    now: datetime,
    accent: str,
) -> None:
    try:
        w = canvas.winfo_width()
    except tk.TclError:
        return
    if w < 60:
        canvas.after(20, lambda: _draw_timeline(canvas, today_events, focused, now, accent))
        return

    canvas.delete("all")

    if not today_events:
        canvas.create_text(w // 2, 30, text="No events today",
                           font=("SF Pro Text", 11), fill=_DIM, anchor="center")
        return

    bar_w = w - _L_PAD - _R_PAD

    # ── Time range: fixed 8–18 in local time, extended if events go outside ──
    local_now = now.astimezone()
    rs = local_now.replace(hour=8,  minute=0, second=0, microsecond=0)
    re = local_now.replace(hour=18, minute=0, second=0, microsecond=0)

    first = min(e.start for e in today_events).astimezone()
    last  = max(e.end   for e in today_events).astimezone()
    rs = min(rs, first.replace(minute=0, second=0, microsecond=0))
    re = max(re, (last + timedelta(minutes=59)).replace(minute=0, second=0, microsecond=0))

    rs_utc   = rs.astimezone(timezone.utc)
    re_utc   = re.astimezone(timezone.utc)
    tot_secs = max((re_utc - rs_utc).total_seconds(), 1)

    def t2x(t: datetime) -> float:
        return _L_PAD + max(0.0, min(float(bar_w),
               (t - rs_utc).total_seconds() / tot_secs * bar_w))

    rows_h = len(today_events) * _ROW_H + 6

    # ── Hour gridlines + axis ────────────────────────────────────────────────
    cur = rs
    while cur <= re:
        x = t2x(cur.astimezone(timezone.utc))
        canvas.create_line(x, _AXIS_H, x, _AXIS_H + rows_h, fill="#ebebeb", width=1)
        canvas.create_text(x, _AXIS_H // 2,
                           text=str(cur.hour),
                           font=("SF Pro Text", 8), fill=_DIM, anchor="center")
        cur += timedelta(hours=1)

    # ── "Now" marker — subtle dashed line ────────────────────────────────────
    if rs_utc <= now <= re_utc:
        nx = t2x(now)
        canvas.create_line(nx, 0, nx, _AXIS_H + rows_h,
                           fill="#ffb3af", width=1, dash=(2, 5))

    # ── Event rows ───────────────────────────────────────────────────────────
    overlaps = _overlapping_indices(today_events)

    for i, ev in enumerate(today_events):
        cy = _AXIS_H + i * _ROW_H + _ROW_H // 2
        x1 = t2x(ev.start)
        x2 = t2x(ev.end)

        done       = ev.end   <= now
        active     = ev.start <= now < ev.end
        is_focused = ev.title == focused.title and ev.start == focused.start

        if done:
            color     = "#6e6e73"   # medium-dark grey — readable contrast
            txt_color = "#3a3a3c"
        elif is_focused:
            color     = accent
            txt_color = _PRI
        elif active:
            color     = _GREEN
            txt_color = _PRI
        elif i in overlaps:
            color     = _ORANGE
            txt_color = _PRI
        else:
            color     = _BLUE
            txt_color = _PRI

        bh2    = _BADGE_H // 2
        line_y = cy + bh2          # underline flush at badge bottom

        # Duration underline — same colour, extends to event end
        canvas.create_rectangle(x1, line_y, x2, line_y + _LINE_H,
                                 fill=color, outline="")

        # Rounded badge (BR square) drawn on top, covering underline left end
        _draw_badge(canvas, x1, cy - bh2, x1 + _BADGE_W, line_y, _BADGE_R, color)

        # Badge time — same font size, centered in badge
        time_lbl = ev.start.astimezone().strftime("%H:%M")
        canvas.create_text(x1 + _BADGE_W // 2, cy,
                           text=time_lbl,
                           font=("SF Pro Text", _FONT_SZ, "bold"),
                           fill="#ffffff", anchor="center")

        # Title + duration — right of badge normally, LEFT for events >= 13:00
        dur   = _dur_str(ev)
        label = f"{ev.title}  {dur}" if dur else ev.title
        font  = ("SF Pro Text", _FONT_SZ, "bold") if is_focused else ("SF Pro Text", _FONT_SZ)

        if ev.start.astimezone().hour >= 13:
            canvas.create_text(x1 - 6, cy,
                               text=label, font=font,
                               fill=txt_color, anchor="e")
        else:
            canvas.create_text(x1 + _BADGE_W + 6, cy,
                               text=label, font=font,
                               fill=txt_color, anchor="w")


def show_reminder(
    root: tk.Tk,
    event: "Event",
    today_events: list["Event"] | None = None,
) -> None:
    """Two-column Toplevel: event detail left, pin timeline right. Non-blocking."""
    _play_sound()

    badge_text, accent = _urgency(event)
    now          = datetime.now(timezone.utc)
    today_events = today_events or []

    timeline_h = _AXIS_H + len(today_events) * _ROW_H + 10
    CH = max(230, timeline_h + 54) + 4
    CH = min(CH, 500)
    CW = 720
    sw, sh = root.winfo_screenwidth(), root.winfo_screenheight()

    win = tk.Toplevel(root)
    win.title("Meeting Reminder")
    win.geometry(f"{CW}x{CH}+{(sw - CW) // 2}+{(sh - CH) // 2}")
    win.resizable(False, False)
    win.configure(bg=_RIGHT_BG)
    win.attributes("-topmost", True)
    win.lift()
    win.after(50, win.focus_force)

    def dismiss(*_):
        win.destroy()

    tk.Frame(win, bg=accent, height=4).pack(fill="x")

    cols = tk.Frame(win, bg=_RIGHT_BG)
    cols.pack(fill="both", expand=True)

    # ── Left column ──────────────────────────────────────────────────────────
    LEFT_W = 210
    left = tk.Frame(cols, bg=_LEFT_BG, width=LEFT_W)
    left.pack(side="left", fill="y")
    left.pack_propagate(False)

    lb = tk.Frame(left, bg=_LEFT_BG, padx=18, pady=16)
    lb.pack(fill="both", expand=True)

    pill = tk.Frame(lb, bg=accent, padx=8, pady=2)
    pill.pack(anchor="w")
    tk.Label(pill, text=badge_text, font=("SF Pro Text", 9, "bold"),
             fg="#ffffff", bg=accent).pack()

    tk.Label(lb, text=event.title,
             font=("SF Pro Display", 16, "bold"),
             fg=_PRI, bg=_LEFT_BG,
             wraplength=175, justify="left").pack(anchor="w", pady=(10, 0))

    dur = _dur_str(event)
    tk.Label(lb, text=dur, font=("SF Pro Text", 12), fg=_SEC,
             bg=_LEFT_BG).pack(anchor="w", pady=(4, 0))

    btn_f = tk.Frame(lb, bg=_LEFT_BG)
    btn_f.pack(side="bottom", fill="x")
    _label_btn(btn_f, "Dismiss", accent, dismiss).pack(side="right")

    tk.Frame(cols, bg=_SEP, width=1).pack(side="left", fill="y")

    # ── Right column ─────────────────────────────────────────────────────────
    right = tk.Frame(cols, bg=_RIGHT_BG)
    right.pack(side="left", fill="both", expand=True)

    rh = tk.Frame(right, bg=_RIGHT_BG, padx=12, pady=9)
    rh.pack(fill="x")
    tk.Label(rh, text=datetime.now().strftime("%A, %b %-d"),
             font=("SF Pro Text", 11, "bold"),
             fg=_SEC, bg=_RIGHT_BG).pack(anchor="w")
    tk.Frame(right, bg=_SEP, height=1).pack(fill="x", padx=12)

    canvas = tk.Canvas(right, bg=_RIGHT_BG, highlightthickness=0,
                       height=timeline_h)
    canvas.pack(fill="x", padx=4, pady=(4, 6))

    win.after(10, lambda: _draw_timeline(canvas, today_events, event, now, accent))

    win.protocol("WM_DELETE_WINDOW", dismiss)
    win.bind("<Escape>", dismiss)
    win.bind("<Return>", dismiss)
