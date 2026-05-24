#!/bin/bash
# Watch Sources/ for changes and hot-reload the app.
# Usage: ./watch.sh
set -e
cd "$(dirname "$0")"

BINARY=.build/debug/CalendarBlocker
STAMP=$(mktemp /tmp/cb_watch_stamp.XXXXXX)
PID=""

kill_app() {
    [ -n "$PID" ] && kill "$PID" 2>/dev/null || true
    PID=""
}

build_and_run() {
    kill_app
    printf '\033[1;34m» Building...\033[0m\n'
    local output
    output=$(swift build 2>&1)
    local build_ok=$?
    echo "$output" | grep -v '^$' || true
    if [ $build_ok -eq 0 ]; then
        printf '\033[1;32m» Launching\033[0m\n'
        "$BINARY" &
        PID=$!
    else
        printf '\033[1;31m» Build failed — keeping old binary\033[0m\n'
    fi
    touch "$STAMP"
}

trap 'kill_app; rm -f "$STAMP"; exit' INT TERM

# Initial build
build_and_run

printf '\033[2m» Watching Sources/ — save any .swift file to reload\033[0m\n'
while true; do
    sleep 1
    CHANGED=$(find Sources -name "*.swift" -newer "$STAMP" 2>/dev/null)
    if [ -n "$CHANGED" ]; then
        printf '\033[2m» %s changed\033[0m\n' "$CHANGED"
        build_and_run
    fi
done
