#!/usr/bin/env bash
# Boop doctor: agent-agnostic self-diagnosis of the current harness.
#
# Answers one question: "if I run an agent in this harness right now, will
# Boop see it?" Runs the same way from Claude Code, Codex, Cursor, or a
# plain terminal. Exit 0 = healthy, 1 = something is broken, 2 = armed and
# waiting for the confirm step (see --confirm).
#
# Usage:
#   skills/doctor/doctor.sh [--agent claude-code|codex|cursor] [--device] [--json] [--headless]
#   skills/doctor/doctor.sh --confirm      # after the harness fired a tool call
#
# Two-step live check. Step 1 (default run) verifies config, hooks, the app,
# auth, and a synthetic round trip, then ARMS by recording the app's state
# version. The agent then runs one harmless tool call in its own harness
# (e.g. `echo BOOP_DOCTOR_PING`). Step 2 (--confirm) checks that the app's
# state moved, which proves the harness's own hooks fire.
set -uo pipefail

AGENT=""; DEVICE=0; JSON=0; CONFIRM=0; HEADLESS=0; STARTED=0; KEEP_RUNNING=0
while [ $# -gt 0 ]; do
  case "$1" in
    --agent) AGENT="$2"; shift 2 ;;
    --device) DEVICE=1; shift ;;
    --json) JSON=1; shift ;;
    --headless) HEADLESS=1; shift ;;
    --confirm) CONFIRM=1; shift ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

CFG="$HOME/.boop/config.json"
HOOK="$HOME/.boop/boop-hook.sh"
ARM="/tmp/boop-doctor.arm"
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
pass=0; fail=0; warn=0; results=()
ok()   { pass=$((pass+1)); results+=("ok|$1"); [ $JSON -eq 1 ] || printf '  \033[32m✓\033[0m %s\n' "$1"; }
bad()  { fail=$((fail+1)); results+=("fail|$1"); [ $JSON -eq 1 ] || printf '  \033[31m✗\033[0m %s\n' "$1"; }
note() { warn=$((warn+1)); results+=("warn|$1"); [ $JSON -eq 1 ] || printf '  \033[33m!\033[0m %s\n' "$1"; }
info() { [ $JSON -eq 1 ] || printf '  \033[2m·\033[0m %s\n' "$1"; }
hdr()  { [ $JSON -eq 1 ] || printf '\n\033[1m%s\033[0m\n' "$1"; }

# --- detect harness -------------------------------------------------------
if [ -z "$AGENT" ]; then
  if [ -n "${CLAUDECODE:-}" ] || [ -n "${CLAUDE_CODE_ENTRYPOINT:-}" ]; then AGENT=claude-code
  elif [ -n "${CODEX_SANDBOX:-}" ] || [ -n "${CODEX_THREAD_ID:-}" ] || [ -n "${CODEX_HOME:-}" ]; then AGENT=codex
  elif [ -n "${CURSOR_AGENT:-}" ] || [ -n "${CURSOR_TRACE_ID:-}" ]; then AGENT=cursor
  else AGENT=unknown; fi
fi

PORT=$(grep -o '"port" *: *[0-9]*' "$CFG" 2>/dev/null | head -1 | grep -o '[0-9]*')
TOKEN=$(grep -o '"token" *: *"[^"]*"' "$CFG" 2>/dev/null | head -1 | sed 's/.*"token" *: *"//; s/".*//')
PORT="${PORT:-21321}"
BASE="http://127.0.0.1:${PORT}"
CURL=(curl -s --noproxy '*' --connect-timeout 2 --max-time 5)
version() { "${CURL[@]}" "$BASE/healthz" 2>/dev/null | grep -o '"stateVersion":[0-9]*' | grep -o '[0-9]*'; }

# Keep a doctor-owned app alive between arm and confirm; cleanup on failure or confirm.
cleanup_headless() {
  if [ "$STARTED" = 1 ] && [ "$KEEP_RUNNING" = 0 ]; then
    "$REPO/app/tools/headless-shared-hooks.sh" --stop >&2
  fi
}
trap cleanup_headless EXIT
if [ "$HEADLESS" = 1 ] && [ "$CONFIRM" = 0 ] && [ -z "$(version)" ]; then
  "$REPO/app/tools/headless-shared-hooks.sh" >&2 || exit 1
  STARTED=1
  PORT=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("port",21321))' "$CFG")
  TOKEN=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["token"])' "$CFG")
  BASE="http://127.0.0.1:${PORT}"
fi

# --- confirm step ---------------------------------------------------------
if [ $CONFIRM -eq 1 ]; then
  hdr "Boop doctor: confirm"
  if [ ! -f "$ARM" ]; then bad "not armed; run skills/doctor/doctor.sh first"; exit 1; fi
  read -r ARMED_V ARMED_AGENT ARMED_AT OWNED_PID < "$ARM"
  # Only stop the same process this doctor started, never a replacement instance.
  if [ -n "${OWNED_PID:-}" ] && [ "$OWNED_PID" != 0 ] &&
      [ "$(cat /tmp/boop-headless.pid 2>/dev/null)" = "$OWNED_PID" ]; then STARTED=1; fi
  RECENT=$(mktemp) || exit 1
  CODE=$("${CURL[@]}" -H "X-Boop-Token: $TOKEN" -o "$RECENT" -w '%{http_code}' "$BASE/diag/recent?n=500")
  MATCH=0
  if [ "$CODE" = 200 ]; then
    if python3 - "$RECENT" "$ARMED_AGENT" "${ARMED_AT:-0}" <<'PYCODE'
import json,sys
entries=json.load(open(sys.argv[1]))["entries"]
sys.exit(0 if any(e["source"]==sys.argv[2] and e["timestamp"]>float(sys.argv[3]) for e in entries) else 1)
PYCODE
    then MATCH=1; fi
  elif [ "$CODE" = 404 ]; then
    NOW_V=$(version)
    info '/diag/recent unavailable; falling back to version delta'
    if [ -n "$NOW_V" ] && [ "$NOW_V" -gt "$ARMED_V" ]; then MATCH=1; fi
  else
    bad "diagnostics request failed (HTTP $CODE); cannot confirm hooks"
  fi
  rm -f "$RECENT" "$ARM"
  if [ "$MATCH" = 1 ]; then
    ok "harness '$ARMED_AGENT' hooks fired since arming"; exit 0
  fi
  bad "no hook reached Boop from '$ARMED_AGENT' since arming"
  info "run a tool call after arming; if hooks are stale, reinstall them and restart the harness"
  exit 1
fi

# --- 1. config --------------------------------------------------------------
hdr "Boop doctor  (harness: $AGENT)"
hdr "1. Config"
if [ -f "$CFG" ]; then ok "$CFG present"; else bad "$CFG missing: open Boop once to create it"; fi
[ -n "$TOKEN" ] && ok "token present" || bad "no token in config.json"
grep -q '"approvalMode" *: *true' "$CFG" 2>/dev/null && info "approval mode: on (Boop answers PermissionRequest)" || info "approval mode: off (agents show their own prompts)"

# --- 2. hook script ---------------------------------------------------------
hdr "2. Hook script"
if [ -x "$HOOK" ]; then ok "$HOOK executable ($(sed -n '2p' "$HOOK" | sed 's/^# //'))"; else bad "$HOOK missing or not executable: Boop > Settings > install hooks"; fi

HOOK_VERSION=$(sed -n 's/^# boop-hook v\([0-9][0-9]*\).*/\1/p' "$HOOK" 2>/dev/null | head -1)
info "hook script version: ${HOOK_VERSION:-unknown}"
HEALTH=$("${CURL[@]}" "$BASE/healthz" 2>/dev/null)
if [ -z "$HEALTH" ]; then
  REQUIRED_HOOK_VERSION=6
else
  REQUIRED_HOOK_VERSION=$(printf '%s' "$HEALTH" | grep -o '"hookVersion" *: *[0-9]*' | grep -o '[0-9]*')
fi
if [ -z "$REQUIRED_HOOK_VERSION" ]; then
  bad 'running app does not report hookVersion; update Boop'
elif [ "${HOOK_VERSION:-0}" -lt "$REQUIRED_HOOK_VERSION" ]; then
  bad "hook script must be v${REQUIRED_HOOK_VERSION} or newer; repair hooks in Boop Settings"
fi

# --- 3. registration in this harness ---------------------------------------
hdr "3. Hook registration"
check_file_has() { # file label expected...
  local f="$1" label="$2"; shift 2
  if [ ! -f "$f" ]; then bad "$label missing ($f)"; return; fi
  local missing=()
  for ev in "$@"; do grep -q "\"$ev\"" "$f" || missing+=("$ev"); done
  if grep -q "boop-hook.sh\|BoopSignal" "$f"; then
    [ ${#missing[@]} -eq 0 ] && ok "$label registers boop for all expected events" || note "$label has boop but lacks: ${missing[*]}"
  else bad "$label does not reference boop; reinstall hooks"; fi
}
case "$AGENT" in
  claude-code) check_file_has "$HOME/.claude/settings.json" "~/.claude/settings.json" SessionStart UserPromptSubmit Stop SessionEnd PostToolUse PermissionRequest Notification ;;
  codex)       check_file_has "$HOME/.codex/hooks.json" "~/.codex/hooks.json" SessionStart Stop PermissionRequest ;;
  cursor)      check_file_has "$HOME/.cursor/hooks.json" "~/.cursor/hooks.json" beforeShellExecution stop ;;
  *) note "harness unknown; pass --agent to check registration. Checking all three:"
     check_file_has "$HOME/.claude/settings.json" "claude" SessionStart Stop
     check_file_has "$HOME/.codex/hooks.json" "codex" SessionStart Stop
     [ -f "$HOME/.cursor/hooks.json" ] && check_file_has "$HOME/.cursor/hooks.json" "cursor" stop || info "cursor: no ~/.cursor/hooks.json (fine if Cursor is not used)" ;;
esac

# --- 4. app -----------------------------------------------------------------
hdr "4. App"
V0=$(version)
if [ -n "$V0" ]; then ok "Boop app reachable at $BASE (state v$V0)"; else
  bad "Boop app not reachable at $BASE"
  info "retry with --headless to start Boop without GUI or Bluetooth"
  hdr "Summary"; info "$pass ok, $fail failed, $warn warnings"; exit 1
fi
CODE=$("${CURL[@]}" -o /dev/null -w '%{http_code}' -X POST "$BASE/hook/event?source=doctor" -H 'Content-Type: application/json' -d '{"hook_event_name":"Noop"}')
[ "$CODE" = "401" ] && ok "unauthenticated hook is rejected (401)" || note "unauthenticated hook returned $CODE (expected 401)"
CODE=$("${CURL[@]}" -o /dev/null -w '%{http_code}' -X POST "$BASE/hook/event?source=doctor" -H 'Content-Type: application/json' -H "X-Boop-Token: $TOKEN" -d '{"hook_event_name":"Noop"}')
[ "$CODE" = "200" ] && ok "authenticated hook accepted (200)" || bad "authenticated hook returned $CODE"

# --- 5. synthetic round trip through the installed script -------------------
hdr "5. Synthetic round trip"
SRC="$AGENT"; [ "$SRC" = "unknown" ] && SRC="claude-code"
SID="doctor-$$-$(date +%s)"
V1=$(version)
printf '{"hook_event_name":"SessionStart","session_id":"%s","cwd":"%s"}' "$SID" "$REPO" | "$HOOK" "$SRC" >/dev/null 2>&1
sleep 0.4; V2=$(version)
if [ -n "$V2" ] && [ "$V2" -gt "$V1" ]; then ok "hook script delivered a SessionStart for source=$SRC (v$V1 -> v$V2)"; else bad "hook script ran but Boop state did not change"; fi
printf '{"hook_event_name":"SessionEnd","session_id":"%s"}' "$SID" | "$HOOK" "$SRC" >/dev/null 2>&1
sleep 0.4

# --- 6. device (optional) ---------------------------------------------------
if [ $DEVICE -eq 1 ]; then
  hdr "6. Device"
  BC="$REPO/archived/firmware/esp32/tools/buddyctl.py"
  if [ -f "$BC" ]; then
    if OUT=$(cd "$REPO/archived/firmware/esp32" && python3 tools/buddyctl.py ping --json 2>/dev/null); then ok "device ping: $(echo "$OUT" | head -c 160)"; else bad "no device answered over USB (plugged in? Boop app quit? see archived/research/eng/TESTING.md §7)"; fi
  else note "buddyctl not found at $BC"; fi
fi

# --- arm for the live confirm ----------------------------------------------
hdr "7. Live harness check (armed)"
# settle so a background tick does not fake a confirm
for i in 1 2 3 4 5; do a=$(version); sleep 1; b=$(version); [ "$a" = "$b" ] && break; done
ARMED_AT=$(python3 -c 'import time; print(time.time()*1000)')
OWNED_PID=0
if [ "$STARTED" = 1 ] && [ "$fail" = 0 ]; then
  OWNED_PID=$(cat /tmp/boop-headless.pid)
  KEEP_RUNNING=1
fi
umask 077
printf '%s %s %s %s\n' "$b" "$AGENT" "$ARMED_AT" "$OWNED_PID" > "$ARM"
info "armed at state v$b for harness '$AGENT'"
info "NEXT: run one harmless tool call in this harness, e.g.:  echo BOOP_DOCTOR_PING"
info "THEN: skills/doctor/doctor.sh --confirm"

hdr "Summary"
info "$pass ok, $fail failed, $warn warnings"
[ $JSON -eq 1 ] && printf '{"agent":"%s","ok":%d,"fail":%d,"warn":%d,"armed":%s}\n' "$AGENT" "$pass" "$fail" "$warn" "${b:-null}"
[ $fail -eq 0 ] && exit 2 || exit 1
