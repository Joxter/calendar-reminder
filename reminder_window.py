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


def show_reminder(root: tk.Tk, event: "Event") -> None:
    """Create a Toplevel reminder window. Non-blocking — returns immediately."""
    _play_sound()

    win = tk.Toplevel(root)
    win.title("Meeting Reminder")

    cw, ch = 560, 300
    sw = win.winfo_screenwidth()
    sh = win.winfo_screenheight()
    win.geometry(f"{cw}x{ch}+{(sw - cw) // 2}+{(sh - ch) // 2}")
    win.resizable(False, False)
    win.configure(bg="#ffffff")
    win.attributes("-topmost", True)
    win.lift()
    win.after(50, win.focus_force)

    badge_text, accent = _urgency(event)

    def dismiss(*_):
        win.destroy()

    # Accent stripe
    tk.Frame(win, bg=accent, height=4).pack(fill="x")

    # Body
    body = tk.Frame(win, bg="#ffffff", padx=32, pady=24)
    body.pack(fill="both", expand=True)

    # Urgency badge
    pill = tk.Frame(body, bg=accent, padx=9, pady=3)
    pill.pack(anchor="w")
    tk.Label(pill, text=badge_text,
             font=("SF Pro Text", 10, "bold"),
             fg="#ffffff", bg=accent).pack()

    # Event title
    tk.Label(body, text=event.title,
             font=("SF Pro Display", 22, "bold"),
             fg="#111827", bg="#ffffff",
             wraplength=480, justify="left").pack(anchor="w", pady=(12, 0))

    # Hairline divider
    tk.Frame(body, bg="#e5e7eb", height=1).pack(fill="x", pady=(14, 10))

    # Time
    local_start = event.start.astimezone().strftime("%H:%M")
    local_end = event.end.astimezone().strftime("%H:%M")
    tk.Label(body, text=f"{local_start}  –  {local_end}",
             font=("SF Pro Text", 14), fg="#6b7280", bg="#ffffff").pack(anchor="w")

    # Footer
    footer = tk.Frame(body, bg="#ffffff")
    footer.pack(side="bottom", fill="x")

    tk.Label(footer, text="Press Esc to dismiss",
             font=("SF Pro Text", 10), fg="#d1d5db", bg="#ffffff").pack(side="left")

    tk.Button(
        footer, text="Dismiss",
        font=("SF Pro Text", 12, "bold"),
        fg="#ffffff", bg=accent,
        activebackground=accent, activeforeground="#ffffff",
        relief="flat", bd=0,
        padx=18, pady=8,
        cursor="hand2",
        command=dismiss,
    ).pack(side="right")

    win.protocol("WM_DELETE_WINDOW", dismiss)
    win.bind("<Escape>", dismiss)
    win.bind("<Return>", dismiss)
