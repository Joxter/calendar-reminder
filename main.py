#!/usr/bin/env python3
"""Calendar Blocker — aggressive fullscreen meeting reminders."""

from __future__ import annotations

import logging
import time

import config
from calendar_checker import Event, fetch_upcoming_events, fetch_next_event
from datetime import datetime, timezone, timedelta
from reminder_window import show_reminder

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)
logger = logging.getLogger(__name__)


def main() -> None:
    if not config.ICAL_URL:
        raise SystemExit(
            "ICAL_URL is not set.\n"
            "Export it before running:\n"
            "  export ICAL_URL='https://calendar.google.com/calendar/ical/...'"
        )

    logger.info(
        "Calendar Blocker started. Polling every %ds, warning %ds before events.",
        config.POLL_INTERVAL,
        config.WARNING_THRESHOLD,
    )

    # Show a fake event immediately so the window can be tested without waiting
    now = datetime.now(timezone.utc)
    test_event = Event(
        title="Design Review",
        start=now + timedelta(minutes=7),
        end=now + timedelta(minutes=37),
    )
    logger.info("Showing test reminder window…")
    show_reminder(test_event)

    # Track which events we've already shown a reminder for (by start timestamp)
    shown: set[str] = set()

    while True:
        logger.info("Checking calendar…")
        events = fetch_upcoming_events()

        for event in events:
            key = f"{event.title}|{event.start.isoformat()}"
            if key in shown:
                continue

            logger.info("Reminding: %s at %s", event.title, event.start.strftime("%H:%M"))
            shown.add(key)
            show_reminder(event)  # blocks until dismissed

        # Prune shown set — drop events that ended more than an hour ago
        # (avoids unbounded growth on long-running sessions)
        if len(shown) > 200:
            shown.clear()

        next_event = fetch_next_event()
        if next_event:
            secs = next_event.starts_in_seconds
            h, rem = divmod(int(secs), 3600)
            m, s = divmod(rem, 60)
            if h:
                time_str = f"in {h}h {m}m"
            elif m:
                time_str = f"in {m}m {s}s"
            else:
                time_str = f"in {s}s"
            local_start = next_event.start.astimezone().strftime("%H:%M")
            logger.info("Next event: \"%s\" at %s (%s)", next_event.title, local_start, time_str)
        else:
            logger.info("No upcoming events found.")

        logger.info("Next check in %ds.", config.POLL_INTERVAL)
        time.sleep(config.POLL_INTERVAL)


if __name__ == "__main__":
    main()
