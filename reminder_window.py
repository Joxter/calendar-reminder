from __future__ import annotations

import subprocess
import tkinter as tk
from datetime import timezone
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from calendar_checker import Event


def _play_sound() -> None:
    """Play the macOS system alert sound non-blocking."""
    try:
        subprocess.Popen(
            ["afplay", "/System/Library/Sounds/Glass.aiff"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except FileNotFoundError:
        pass  # non-macOS or afplay missing — silent degradation


def _format_time(event: "Event") -> str:
    local_start = event.start.astimezone().strftime("%H:%M")
    local_end = event.end.astimezone().strftime("%H:%M")
    return f"{local_start} – {local_end}"


def show_reminder(event: "Event") -> None:
    """
    Block until the user dismisses the fullscreen reminder for *event*.
    Safe to call from the main thread.
    """
    _play_sound()

    root = tk.Tk()
    root.title("Upcoming Meeting")

    # --- Fullscreen, always-on-top, focus-stealing ---
    root.attributes("-fullscreen", True)
    root.attributes("-topmost", True)
    root.attributes("-alpha", 0.97)
    root.configure(bg="#1a1a2e")

    # Force focus once the window is mapped
    root.after(100, root.focus_force)
    root.after(150, lambda: root.lift())

    screen_w = root.winfo_screenwidth()
    screen_h = root.winfo_screenheight()

    # Outer frame centres content vertically
    frame = tk.Frame(root, bg="#1a1a2e")
    frame.place(relx=0.5, rely=0.5, anchor="center")

    seconds_until = event.starts_in_seconds
    if seconds_until <= 0:
        urgency_text = "MEETING IN PROGRESS"
        urgency_color = "#ff4757"
    elif seconds_until <= 120:
        urgency_text = f"STARTING IN {int(seconds_until // 60)}m {int(seconds_until % 60)}s"
        urgency_color = "#ff6b35"
    else:
        mins = int(seconds_until // 60)
        urgency_text = f"STARTING IN {mins} MINUTES"
        urgency_color = "#ffa502"

    tk.Label(
        frame,
        text=urgency_text,
        font=("SF Pro Display", 28, "bold"),
        fg=urgency_color,
        bg="#1a1a2e",
        pady=10,
    ).pack()

    tk.Label(
        frame,
        text=event.title,
        font=("SF Pro Display", 52, "bold"),
        fg="#ffffff",
        bg="#1a1a2e",
        wraplength=int(screen_w * 0.8),
        justify="center",
        pady=20,
    ).pack()

    tk.Label(
        frame,
        text=_format_time(event),
        font=("SF Pro Display", 32),
        fg="#a4b0be",
        bg="#1a1a2e",
        pady=8,
    ).pack()

    # Pulsing red border hint — a thin coloured bar at top and bottom
    for rely in (0.0, 1.0):
        anchor = "nw" if rely == 0.0 else "sw"
        bar = tk.Frame(root, bg=urgency_color, height=8)
        bar.place(relx=0, rely=rely, relwidth=1.0, anchor=anchor)

    dismiss_btn = tk.Button(
        frame,
        text="Dismiss",
        font=("SF Pro Display", 20),
        fg="#ffffff",
        bg="#2f3542",
        activebackground="#57606f",
        activeforeground="#ffffff",
        relief="flat",
        padx=40,
        pady=14,
        cursor="hand2",
        command=root.destroy,
    )
    dismiss_btn.pack(pady=40)

    # Keyboard shortcut: Escape or Enter also dismisses
    root.bind("<Escape>", lambda _e: root.destroy())
    root.bind("<Return>", lambda _e: root.destroy())

    root.mainloop()
