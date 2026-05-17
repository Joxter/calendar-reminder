from __future__ import annotations

import subprocess
import tkinter as tk
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from calendar_checker import Event


def _play_sound() -> None:
    try:
        subprocess.Popen(
            ["afplay", "/System/Library/Sounds/Glass.aiff"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
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


def _darken(hex_color: str, factor: float = 0.82) -> str:
    """Return a darker shade of a hex color for hover states."""
    r = int(hex_color[1:3], 16)
    g = int(hex_color[3:5], 16)
    b = int(hex_color[5:7], 16)
    return f"#{int(r*factor):02x}{int(g*factor):02x}{int(b*factor):02x}"


def _label_button(parent: tk.Widget, text: str, bg: str, command) -> tk.Label:
    """
    tk.Button ignores bg on macOS (Aqua overrides it).
    A Label with bindings renders colour correctly everywhere.
    """
    hover = _darken(bg)
    btn = tk.Label(
        parent,
        text=text,
        font=("SF Pro Text", 13, "bold"),
        fg="#ffffff",
        bg=bg,
        padx=20,
        pady=9,
        cursor="hand2",
    )
    btn.bind("<Button-1>", lambda _e: command())
    btn.bind("<Enter>",    lambda _e: btn.configure(bg=hover))
    btn.bind("<Leave>",    lambda _e: btn.configure(bg=bg))
    return btn


def show_reminder(root: tk.Tk, event: "Event") -> None:
    """Create a Toplevel reminder window. Non-blocking — returns immediately."""
    _play_sound()

    win = tk.Toplevel(root)
    win.title("Meeting Reminder")

    cw, ch = 520, 240
    sw = win.winfo_screenwidth()
    sh = win.winfo_screenheight()
    win.geometry(f"{cw}x{ch}+{(sw - cw) // 2}+{(sh - ch) // 2}")
    win.resizable(False, False)
    win.configure(bg="#f5f5f7")   # macOS light gray background
    win.attributes("-topmost", True)
    win.lift()
    win.after(50, win.focus_force)

    badge_text, accent = _urgency(event)

    def dismiss(*_):
        win.destroy()

    # ── Accent stripe ────────────────────────────────────────────────────────
    tk.Frame(win, bg=accent, height=4).pack(fill="x")

    # ── Body ─────────────────────────────────────────────────────────────────
    body = tk.Frame(win, bg="#f5f5f7", padx=28, pady=20)
    body.pack(fill="both", expand=True)

    # Top row: badge pill + time (right-aligned)
    top_row = tk.Frame(body, bg="#f5f5f7")
    top_row.pack(fill="x")

    pill = tk.Frame(top_row, bg=accent, padx=8, pady=2)
    pill.pack(side="left")
    tk.Label(pill, text=badge_text,
             font=("SF Pro Text", 10, "bold"),
             fg="#ffffff", bg=accent).pack()

    local_start = event.start.astimezone().strftime("%H:%M")
    local_end   = event.end.astimezone().strftime("%H:%M")
    tk.Label(top_row, text=f"{local_start} – {local_end}",
             font=("SF Pro Text", 12),
             fg="#86868b", bg="#f5f5f7").pack(side="right", padx=2)

    # Event title
    tk.Label(body, text=event.title,
             font=("SF Pro Display", 20, "bold"),
             fg="#1d1d1f", bg="#f5f5f7",
             wraplength=460, justify="left").pack(anchor="w", pady=(10, 0))

    # ── Footer ───────────────────────────────────────────────────────────────
    footer = tk.Frame(body, bg="#f5f5f7")
    footer.pack(side="bottom", fill="x", pady=(16, 0))

    tk.Label(footer, text="Esc  ·  click to dismiss",
             font=("SF Pro Text", 10),
             fg="#c7c7cc", bg="#f5f5f7").pack(side="left")

    _label_button(footer, "Dismiss", accent, dismiss).pack(side="right")

    win.protocol("WM_DELETE_WINDOW", dismiss)
    win.bind("<Escape>", dismiss)
    win.bind("<Return>", dismiss)
