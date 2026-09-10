#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
action=start
[ "${1:-}" != --stop ] || action=stop
exec python3 "$ROOT/tools/dev/instance.py" "$action"
