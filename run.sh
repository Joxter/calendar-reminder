#!/bin/bash
# Build (if needed) and run the Swift native version
set -eo pipefail
cd "$(dirname "$0")"
swift build -c release 2>&1 | grep -v "^$"
exec .build/release/CalendarBlocker "$@"
