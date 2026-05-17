#!/usr/bin/env python3
"""Calendar Blocker — aggressive meeting reminders."""

from __future__ import annotations

import logging
import threading
import time
import tkinter as tk
from datetime import datetime, timezone, timedelta

import config
from calendar_checker import Event, fetch_upcoming_events, fetch_next_event
from reminder_window import show_reminder

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)
logger = logging.getLogger(__name__)


def _poll_loop(root: tk.Tk, shown: set[str]) -> None:
    """Runs in a background thread. Schedules reminders onto the main thread via after()."""
    lock = threading.Lock()

    while True:
        logger.info("Checking calendar…")
        events = fetch_upcoming_events()

        for event in events:
            key = f"{event.title}|{event.start.isoformat()}"
            with lock:
                if key in shown:
                    continue
                shown.add(key)
            logger.info("Reminding: %s at %s", event.title, event.start.strftime("%H:%M"))
            # Must create tkinter windows on the main thread
            root.after(0, lambda e=event: show_reminder(root, e))

        if len(shown) > 200:
            shown.clear()

        next_event = fetch_next_event()
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

    # Persistent hidden root — owns the event loop for the entire app lifetime.
    # Polling and sleeping happen in a daemon thread; reminders are Toplevels.
    root = tk.Tk()
    root.withdraw()

    shown: set[str] = set()

    # Test reminder shown immediately on startup
    now = datetime.now(timezone.utc)
    test_event = Event(
        title="Design Review",
        start=now + timedelta(minutes=7),
        end=now + timedelta(minutes=37),
    )
    root.after(200, lambda: show_reminder(root, test_event))

    # Polling runs in background so the main thread never blocks
    t = threading.Thread(target=_poll_loop, args=(root, shown), daemon=True)
    t.start()

    root.mainloop()


if __name__ == "__main__":
    main()
