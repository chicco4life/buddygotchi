#!/usr/bin/env bash
# Keep ownership explicit so cleanup never stops an already-running GUI app.
set -uo pipefail
APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PID_FILE=/tmp/boop-headless.pid
LOG_FILE=/tmp/boop-headless.log
if [ "${1:-}" = --stop ]; then
    [ -f "$PID_FILE" ] || exit 0
    read -r pid < "$PID_FILE"
    case "$pid" in ''|*[!0-9]*) echo 'Invalid headless PID file' >&2; exit 1 ;; esac
    if kill -0 "$pid" 2>/dev/null; then
        case "$(ps -p "$pid" -o command=)" in
            *Boop*--headless*) kill "$pid" || exit 1 ;;
            *) echo 'PID no longer belongs to headless Boop' >&2; exit 1 ;;
        esac
        for i in {1..50}; do
            kill -0 "$pid" 2>/dev/null || break
            sleep 0.1
        done
        if kill -0 "$pid" 2>/dev/null; then echo 'Headless Boop did not stop' >&2; exit 1; fi
    fi
    rm -f "$PID_FILE"
    exit 0
fi
if [ -f "$PID_FILE" ]; then
    read -r pid < "$PID_FILE"
    case "$pid" in ''|*[!0-9]*) ;; *)
        if kill -0 "$pid" 2>/dev/null; then echo 'Headless Boop already has a live PID' >&2; exit 1; fi ;;
    esac
    rm -f "$PID_FILE"
fi
cd "$APP_DIR" || exit 1
swift build --product Boop || exit 1
BIN_DIR="$(swift build --show-bin-path)" || exit 1
nohup "$BIN_DIR/Boop" --headless > "$LOG_FILE" 2>&1 &
pid=$!
printf '%s\n' "$pid" > "$PID_FILE"
deadline=$((SECONDS + 30))
while [ "$SECONDS" -lt "$deadline" ]; do
    if ! kill -0 "$pid" 2>/dev/null; then break; fi
    port="$(python3 -c 'import json,os; print(json.load(open(os.path.expanduser("~/.boop/config.json"))).get("port",21321))' 2>/dev/null)"
    if [ -n "$port" ] && grep -q "boop: listening on 127.0.0.1:$port (headless)" "$LOG_FILE" &&
        curl -fsS --noproxy '*' --connect-timeout 1 --max-time 1 "http://127.0.0.1:$port/healthz" >/dev/null 2>&1; then
        echo "Headless Boop ready (PID $pid, log $LOG_FILE)"
        exit 0
    fi
    sleep 0.2
done
echo "Headless Boop failed to become ready; see $LOG_FILE" >&2
"$0" --stop
exit 1
