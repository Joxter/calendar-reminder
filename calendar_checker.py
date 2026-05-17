from __future__ import annotations

import logging
from dataclasses import dataclass
from datetime import datetime, timezone, timedelta

import requests
from icalendar import Calendar

import config

logger = logging.getLogger(__name__)


@dataclass
class Event:
    title: str
    start: datetime
    end: datetime

    @property
    def starts_in_seconds(self) -> float:
        now = datetime.now(timezone.utc)
        return (self.start - now).total_seconds()

    @property
    def has_started(self) -> bool:
        return self.starts_in_seconds <= 0


def _to_utc(dt) -> datetime:
    """Normalise a date or datetime to a timezone-aware UTC datetime."""
    if isinstance(dt, datetime):
        if dt.tzinfo is None:
            # Assume local time, attach UTC (safe enough for reminder purposes)
            return dt.replace(tzinfo=timezone.utc)
        return dt.astimezone(timezone.utc)
    # date-only event — treat as midnight UTC
    return datetime(dt.year, dt.month, dt.day, tzinfo=timezone.utc)


def _fetch_all_events(url: str) -> list[Event] | None:
    """Fetch and parse the iCal feed, returning all future+recent events, or None on error."""
    try:
        resp = requests.get(url, timeout=15)
        resp.raise_for_status()
    except requests.RequestException as exc:
        logger.warning("Failed to fetch calendar: %s", exc)
        return None

    try:
        cal = Calendar.from_ical(resp.content)
    except Exception as exc:
        logger.warning("Failed to parse iCal data: %s", exc)
        return None

    now = datetime.now(timezone.utc)
    cutoff = now - timedelta(seconds=config.STARTED_GRACE)

    events: list[Event] = []
    for component in cal.walk():
        if component.name != "VEVENT":
            continue
        raw_start = component.get("DTSTART")
        raw_end = component.get("DTEND")
        if raw_start is None:
            continue
        start = _to_utc(raw_start.dt)
        end = _to_utc(raw_end.dt) if raw_end else start + timedelta(hours=1)
        if start >= cutoff:
            title = str(component.get("SUMMARY", "(No title)"))
            events.append(Event(title=title, start=start, end=end))

    events.sort(key=lambda e: e.start)
    return events


def fetch_upcoming_events() -> list[Event]:
    """Return events starting within the warning window (triggers a reminder)."""
    url = config.ICAL_URL
    if not url:
        logger.error("ICAL_URL is not set. Export it or edit config.py.")
        return []

    events = _fetch_all_events(url)
    if events is None:
        return []

    now = datetime.now(timezone.utc)
    window_end = now + timedelta(seconds=config.WARNING_THRESHOLD)
    window_start = now - timedelta(seconds=config.STARTED_GRACE)

    return [e for e in events if window_start <= e.start <= window_end]


def fetch_next_event() -> Event | None:
    """Return the single next upcoming event regardless of the warning window."""
    url = config.ICAL_URL
    if not url:
        return None

    events = _fetch_all_events(url)
    if not events:
        return None

    now = datetime.now(timezone.utc)
    future = [e for e in events if e.start >= now]
    return future[0] if future else None
