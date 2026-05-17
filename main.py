#!/usr/bin/env python3
"""Calendar Blocker — aggressive meeting reminders."""

from __future__ import annotations

import logging
import threading
import time
import tkinter as tk

import config
from calendar_checker import fetch_calendar_data
from reminder_window import show_reminder

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)
logger = logging.getLogger(__name__)


def _poll_loop(root: tk.Tk, shown: set[str]) -> None:
    """Background thread: fetch calendar once per cycle, schedule reminders on main thread."""
    lock = threading.Lock()

    while True:
        logger.info("Checking calendar…")
        upcoming, today, next_event = fetch_calendar_data()

        for event in upcoming:
            key = f"{event.title}|{event.start.isoformat()}"
            with lock:
                if key in shown:
                    continue
                shown.add(key)
            logger.info("Reminding: %s at %s", event.title, event.start.strftime("%H:%M"))
            root.after(0, lambda e=event, td=today: show_reminder(root, e, td))

        if len(shown) > 200:
            shown.clear()

        if next_event:
            secs = next_event.starts_in_seconds
            h, rem = divmod(int(secs), 3600)
            m, s = divmod(rem, 60)
            time_str = f"in {h}h {m}m" if h else (f"in {m}m {s}s" if m else f"in {s}s")
            local_start = next_event.start.astimezone().strftime("%H:%M")
            logger.info('Next event: "%s" at %s (%s)', next_event.title, local_start, time_str)
        else:
            logger.info("No upcoming events found.")

        logger.info("Next check in %ds.", config.POLL_INTERVAL)
        time.sleep(config.POLL_INTERVAL)


def main() -> None:
    if not config.ICAL_URL:
        raise SystemExit(
            "ICAL_URL is not set.\n"
            "Set it in .env or export ICAL_URL='https://...'"
        )

    logger.info(
        "Calendar Blocker started. Polling every %ds, warning %ds before events.",
        config.POLL_INTERVAL,
        config.WARNING_THRESHOLD,
    )

    root = tk.Tk()
    root.withdraw()

    shown: set[str] = set()

    # Show the next real upcoming event immediately on startup
    def _show_startup() -> None:
        _, today, next_event = fetch_calendar_data()
        if next_event:
            root.after(0, lambda: show_reminder(root, next_event, today))

    threading.Thread(target=_show_startup, daemon=True).start()

    t = threading.Thread(target=_poll_loop, args=(root, shown), daemon=True)
    t.start()

    root.mainloop()


if __name__ == "__main__":
    main()
