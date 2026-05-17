import os
from dotenv import load_dotenv

load_dotenv()

# iCal feed URL — set in .env or as an environment variable
ICAL_URL: str = os.environ.get("ICAL_URL", "")

# How often to poll the calendar (seconds)
POLL_INTERVAL: int = int(os.environ.get("POLL_INTERVAL", "300"))  # 5 minutes

# Show reminder this many seconds before event start
WARNING_THRESHOLD: int = int(os.environ.get("WARNING_THRESHOLD", "600"))  # 10 minutes

# How long (seconds) an already-started event is still shown as a reminder
STARTED_GRACE: int = int(os.environ.get("STARTED_GRACE", "300"))  # 5 minutes after start
