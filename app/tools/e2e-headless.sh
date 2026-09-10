#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
python3 "$ROOT/tools/dev/instance.py" start
exec python3 "$ROOT/tools/dev/instance.py" run -- app/tools/e2e-smoke.sh
