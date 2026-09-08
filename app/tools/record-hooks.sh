#!/usr/bin/env bash
# Recording must not alter the payload delivered to the installed hook.
set -uo pipefail
SOURCE="${1:-}"
case "$SOURCE" in claude-code|codex|cursor) ;; *) echo 'usage: record-hooks.sh claude-code|codex|cursor' >&2; exit 1 ;; esac
FIXTURES="$(cd "$(dirname "$0")/.." && pwd)/Tests/Fixtures/hooks"
umask 077
PAYLOAD="$(mktemp)" || exit 0
trap 'rm -f "$PAYLOAD"' EXIT
cat > "$PAYLOAD"
python3 - "$PAYLOAD" "$FIXTURES" "$SOURCE" <<'PY'
import datetime, json, os, pathlib, re, sys
try:
    payload = json.loads(pathlib.Path(sys.argv[1]).read_bytes())
    home = os.path.expanduser('~')
    def redact(value):
        if isinstance(value, str):
            value = re.sub(re.escape(home) + r'(?=/|$)', '~', value)
            return value.encode('utf-8')[:2048].decode('utf-8', errors='ignore')
        if isinstance(value, list):
            return [redact(v) for v in value]
        if isinstance(value, dict):
            return {k: redact(v) for k, v in value.items()}
        return value
    event = payload.get('hook_event_name', payload.get('hookEventName', 'unknown'))
    event = re.sub(r'[^a-zA-Z0-9_-]', '_', str(event))[:100] or 'unknown'
    directory = pathlib.Path(sys.argv[2]) / sys.argv[3] / datetime.date.today().isoformat()
    directory.mkdir(parents=True, exist_ok=True)
    n = 1
    while True:
        try:
            with (directory / f'{event}-{n}.json').open('x') as f:
                json.dump(redact(payload), f, ensure_ascii=False, indent=4)
                f.write('\n')
            break
        except FileExistsError:
            n += 1
except Exception as error:
    print(f'boop recorder: {error}', file=sys.stderr)
PY
"$HOME/.boop/boop-hook.sh" "$SOURCE" < "$PAYLOAD"
# Preserve the installed hook's fail-open behavior, including if it is missing.
exit 0
