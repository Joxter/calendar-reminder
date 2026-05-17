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


def fetch_calendar_data() -> tuple[list[Event], list[Event], Event | None]:
    """Single HTTP fetch → (upcoming, today, next_event).

    upcoming  — events in the reminder window (trigger alerts)
    today     — all events occurring today (local time), for the panel
    next_event — the single next future event for status logging
    """
    url = config.ICAL_URL
    if not url:
        logger.error("ICAL_URL is not set.")
        return [], [], None

    all_events = _fetch_all_events(url)
    if all_events is None:
        return [], [], None

    now = datetime.now(timezone.utc)

    # Upcoming: reminder window
    window_start = now - timedelta(seconds=config.STARTED_GRACE)
    window_end   = now + timedelta(seconds=config.WARNING_THRESHOLD)
    upcoming = [e for e in all_events if window_start <= e.start <= window_end]

    # Today: any event that overlaps with today in local time
    local_now       = now.astimezone()
    today_start_utc = local_now.replace(hour=0, minute=0, second=0, microsecond=0).astimezone(timezone.utc)
    today_end_utc   = today_start_utc + timedelta(days=1)
    # Include events that started before today's cutoff (re-fetch without grace cutoff)
    today = _fetch_today_events(url, today_start_utc, today_end_utc)

    # Next event
    future = [e for e in all_events if e.start >= now]
    next_event = future[0] if future else None

    return upcoming, today, next_event


def _fetch_today_events(url: str, today_start: datetime, today_end: datetime) -> list[Event]:
    """Fetch all events (no recency cutoff) and filter for today."""
    try:
        resp = requests.get(url, timeout=15)
        resp.raise_for_status()
        cal = Calendar.from_ical(resp.content)
    except Exception as exc:
        logger.warning("Failed to fetch today events: %s", exc)
        return []

    events: list[Event] = []
    for component in cal.walk():
        if component.name != "VEVENT":
            continue
        raw_start = component.get("DTSTART")
        raw_end   = component.get("DTEND")
        if raw_start is None:
            continue
        start = _to_utc(raw_start.dt)
        end   = _to_utc(raw_end.dt) if raw_end else start + timedelta(hours=1)
        if start < today_end and end > today_start:
            events.append(Event(title=str(component.get("SUMMARY", "(No title)")),
                                start=start, end=end))
    events.sort(key=lambda e: e.start)
    return events


# Kept for backwards-compat / direct use in tests
def fetch_upcoming_events() -> list[Event]:
    upcoming, _, _ = fetch_calendar_data()
    return upcoming


def fetch_next_event() -> Event | None:
    _, _, nxt = fetch_calendar_data()
    return nxt
