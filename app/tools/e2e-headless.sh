#!/usr/bin/env bash
# Reuse a running app, but stop only the instance this invocation started.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
port="${BUDDY_PORT:-$(python3 -c 'import json,os; print(json.load(open(os.path.expanduser("~/.boop/config.json"))).get("port",21321))' 2>/dev/null)}"
port="${port:-21321}"
started=0
cleanup() { if [ "$started" = 1 ]; then "$DIR/headless.sh" --stop; fi; }
trap cleanup EXIT
if ! curl -fsS --noproxy '*' --connect-timeout 1 --max-time 2 "http://127.0.0.1:$port/healthz" >/dev/null 2>&1; then
    "$DIR/headless.sh" || exit 1
    started=1
fi
"$DIR/e2e-smoke.sh"
