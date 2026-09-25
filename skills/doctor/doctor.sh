#!/usr/bin/env bash
# Boop doctor (plan/ADAPTERS.md §6): will Boop see this agent's hooks?
#
#   1. Hooks are registered for each agent and point at an existing boop-hook.
#   2. The app is running and its socket accepts.
#   3. A synthetic event goes from boop-hook to the app (seen in its log).
#   4. A harmless command run in the agent shows up in Boop (--confirm).
#
# Usage:
#   skills/doctor/doctor.sh [--agent claude|codex] [--state-dir DIR]
#   skills/doctor/doctor.sh --confirm [--state-dir DIR]
#   skills/doctor/doctor.sh --headless     # checks 1–3 against a throwaway headless app
#
# Exit 0 healthy, 1 broken, 2 armed and waiting for the live step: run one
# harmless command through the agent (echo BOOP_DOCTOR_PING), then --confirm.
# It only reads ~/.claude and ~/.codex. Arming writes one file,
# `doctor-armed`, in the state directory; --confirm removes it.
set -uo pipefail

AGENT=""; STATE=""; CONFIRM=0; HEADLESS=0
while [ $# -gt 0 ]; do
  case "$1" in
    --agent) AGENT="$2"; shift 2 ;;
    --state-dir) STATE="$2"; shift 2 ;;
    --confirm) CONFIRM=1; shift ;;
    --headless) HEADLESS=1; shift ;;
    -h|--help) sed -n '2,19p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
STATE="${STATE:-$HOME/Library/Application Support/Boop}"
pass=0; fail=0
ok()   { pass=$((pass+1)); printf '  \033[32m✓\033[0m %s\n' "$1"; }
bad()  { fail=$((fail+1)); printf '  \033[31m✗\033[0m %s\n' "$1"; }
info() { printf '  \033[2m·\033[0m %s\n' "$1"; }
hdr()  { printf '\n\033[1m%s\033[0m\n' "$1"; }

if [ -z "$AGENT" ]; then
  if [ -n "${CLAUDECODE:-}" ] || [ -n "${CLAUDE_CODE_ENTRYPOINT:-}" ]; then AGENT=claude
  elif [ -n "${CODEX_SANDBOX:-}" ] || [ -n "${CODEX_THREAD_ID:-}" ] || [ -n "${CODEX_HOME:-}" ]; then AGENT=codex
  else AGENT=unknown; fi
fi

if [ $HEADLESS -eq 1 ]; then
  STATE="$(mktemp -d /tmp/boop-doctor.XXXX)"
  BOOP="$REPO/app/.build/debug/Boop"
  [ -x "$BOOP" ] || { echo "no $BOOP; run make build" >&2; exit 1; }
  "$BOOP" --headless --state-dir "$STATE" --brain rules --name Doctor >/dev/null 2>&1 &
  APP_PID=$!
  trap 'kill -TERM $APP_PID 2>/dev/null; wait $APP_PID 2>/dev/null; rm -rf "$STATE"' EXIT
  for _ in $(seq 50); do [ -S "$STATE/boop.sock" ] && break; sleep 0.1; done
fi

SOCK="$STATE/boop.sock"
LOG="$STATE/boop.log"
ARM="$STATE/doctor-armed"

# --- live confirm -----------------------------------------------------------
if [ $CONFIRM -eq 1 ]; then
  hdr "Boop doctor: confirm ($AGENT)"
  if [ ! -f "$ARM" ]; then bad "not armed; run doctor.sh first"; exit 1; fi
  since=$(cat "$ARM")
  rm -f "$ARM"
  if awk -v s="$since" '$0 >= s' "$LOG" 2>/dev/null | grep -v 'doctor-' | grep -q ' hook: '; then
    ok "this agent's hooks reached Boop: $(awk -v s="$since" '$0 >= s' "$LOG" | grep ' hook: ' | grep -v 'doctor-' | tail -1 | cut -d' ' -f3-5)"
    exit 0
  fi
  bad "no hook from the agent reached Boop since arming"
  exit 1
fi

hdr "Boop doctor (agent: $AGENT, state: $STATE)"

# --- 1. hook registration ---------------------------------------------------
hdr "Hooks"
HOOK_BIN=""
check_agent() {
  local name="$1" file="$2"; shift 2
  if [ ! -f "$file" ]; then info "$name: no $file"; return; fi
  local cmds
  cmds=$(python3 - "$file" "$@" <<'PY'
import json, re, sys
path, events = sys.argv[1], sys.argv[2:]
try:
    hooks = json.load(open(path)).get("hooks", {})
except Exception as e:
    print("ERR not JSON: %s" % e); sys.exit()
boop = re.compile(r'(^|/)boop-hook"?(\s|$)')
missing = []
cmds = set()
for ev in events:
    found = [h.get("command", "") for g in hooks.get(ev, []) for h in g.get("hooks", []) if boop.search(h.get("command", ""))]
    if not found: missing.append(ev)
    cmds.update(found)
old = [h.get("command", "") for gs in hooks.values() for g in gs for h in g.get("hooks", []) if "boop-hook.sh" in h.get("command", "")]
print("MISSING " + " ".join(missing) if missing else "ALL")
for c in sorted(cmds): print("CMD " + c)
if old: print("OLD %d" % len(old))
PY
)
  case "$cmds" in ERR*) bad "$name: $file ${cmds#ERR }"; return ;; esac
  local status; status=$(echo "$cmds" | head -1)
  if [ "$status" = "ALL" ]; then ok "$name: every hook registered"; else bad "$name: missing ${status#MISSING }"; fi
  echo "$cmds" | grep -q '^OLD' && bad "$name: previous-generation entries (~/.boop/boop-hook.sh) are still there"
  while read -r line; do
    [ -z "$line" ] && continue
    local c="${line#CMD }" bin
    if [[ $c == \"* ]]; then bin="${c#\"}"; bin="${bin%%\"*}"; else bin="${c%% *}"; fi
    if [ -x "$bin" ]; then ok "$name: $bin exists"; HOOK_BIN="$bin"; else bad "$name: $bin is missing"; fi
  done < <(echo "$cmds" | grep '^CMD')
}
check_agent "Claude Code" "$HOME/.claude/settings.json" SessionStart UserPromptSubmit PreToolUse PostToolUse \
  PostToolUseFailure PermissionRequest Notification Elicitation ElicitationResult Stop StopFailure SessionEnd
check_agent "Codex" "$HOME/.codex/hooks.json" SessionStart UserPromptSubmit PreToolUse PostToolUse PermissionRequest Stop SessionEnd
[ -n "$HOOK_BIN" ] || HOOK_BIN="$REPO/app/.build/debug/boop-hook"

# --- 2. the app -------------------------------------------------------------
hdr "App"
if [ ! -S "$SOCK" ]; then
  bad "no socket at $SOCK: the app isn't running (ask the owner to start Boop; don't launch it from an agent)"
  exit 1
fi
if python3 -c 'import socket,sys; s=socket.socket(socket.AF_UNIX); s.settimeout(0.5); s.connect(sys.argv[1])' "$SOCK" 2>/dev/null; then
  ok "socket accepts at $SOCK"
else
  bad "socket at $SOCK doesn't accept (stale socket? restart Boop)"
  exit 1
fi

# --- 3. synthetic round trip ------------------------------------------------
hdr "Round trip"
start=$(date +%H:%M:%S)
echo "$start" > "$ARM"
session="doctor-$$"
printf '{"hook_event_name":"SessionEnd","session_id":"%s","cwd":"/tmp"}' "$session" \
  | BOOP_SOCKET="$SOCK" "$HOOK_BIN" claude
code=$?
[ $code -eq 0 ] && ok "boop-hook exited 0" || bad "boop-hook exited $code"
seen=0
for _ in $(seq 20); do grep -q "hook: claude SessionEnd $session" "$LOG" 2>/dev/null && { seen=1; break; }; sleep 0.1; done
[ $seen -eq 1 ] && ok "the app received the synthetic event" || bad "the app didn't log the synthetic event (is $LOG this app's log?)"

hdr "Result"
echo "  $pass passed, $fail failed"
if [ $fail -gt 0 ]; then rm -f "$ARM"; exit 1; fi
if [ $HEADLESS -eq 1 ]; then rm -f "$ARM"; exit 0; fi
echo "  Armed. Run one harmless command through the agent (echo BOOP_DOCTOR_PING), then: $0 --confirm"
exit 2
