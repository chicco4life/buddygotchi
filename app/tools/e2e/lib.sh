#!/usr/bin/env bash
#
# Shared helpers for the Boop e2e suites. Source this from each client
# script; it provides the HTTP plumbing, assertions, and summary.
#
CONFIG="${BOOP_STATE_DIR:-$HOME/.boop}/config.json"
PORT="${BUDDY_PORT:-$(python3 -c 'import json,os; print(json.load(open(os.path.join(os.environ.get("BOOP_STATE_DIR", os.path.expanduser("~/.boop")), "config.json"))).get("port",21321))' 2>/dev/null)}"
PORT="${PORT:-21321}"
BASE="http://127.0.0.1:${PORT}"
CURL=(curl -s --noproxy '*' --connect-timeout 2)
TOKEN="$(grep -o '"token" *: *"[^"]*"' "$CONFIG" 2>/dev/null | head -1 | sed 's/.*"token" *: *"//; s/".*//')"
AUTH=()
[ -n "$TOKEN" ] && AUTH=(-H "X-Boop-Token: $TOKEN")
CWD="${BUDDY_E2E_CWD:-/tmp/buddy-e2e}"

pass=0; fail=0
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$1"; fail=$((fail+1)); }
info() { printf '  \033[2m·\033[0m %s\n' "$1"; }
hdr()  { printf '\n\033[1m%s\033[0m\n' "$1"; }

health()  { "${CURL[@]}" "${BASE}/healthz"; }
version() { health | grep -o '"stateVersion":[0-9]*' | grep -o '[0-9]*'; }
desktop() { health | grep -o '"desktop":"[a-z]*"' | sed 's/.*"desktop":"//; s/"//'; }

# Return 4 only for a production app with the debug route disabled.
state_field() {
  local response code
  response="$("${CURL[@]}" --max-time 5 "${AUTH[@]}" -w '\n%{http_code}' "$BASE/state")" || return 1
  code="${response##*$'\n'}"
  [ "$code" != 404 ] || return 4
  [ "$code" = 200 ] || return 1
  printf '%s' "${response%$'\n'*}" | python3 -c '
import json,re,sys
v=json.load(sys.stdin)
for key in re.findall(r"[^.\[\]]+", sys.argv[1]):
    try:
        v=v[int(key)] if isinstance(v,list) else v[key]
    except (KeyError, IndexError, TypeError):
        v=None; break   # optional keys are omitted when nil: print nothing, not a traceback
if v is not None:
    print(v if isinstance(v,str) else json.dumps(v,separators=(",",":")))' "$1"
}
# Assert the creature state after a step. Global by default; when another
# agent was already connected at baseline (D0 != disconnected), the reducer
# collapses across sessions and a foreign working session correctly outranks
# our idle/done, so assert OUR session's state instead ($2 = session id).
#   creature idle → session idle · working → working · needsYou →
#   needsConfirmation · uhoh → errored|thinking · done → session idle AND
#   lastCompletionAt advanced since the step began (LAST_DONE_MARK).
session_state() { # id → state of that session in activeSessions, or ""
  state_field .activeSessions | python3 -c '
import json,sys
for s in json.load(sys.stdin):
    if s.get("id")==sys.argv[1]: print(s.get("state","")); break' "$1" 2>/dev/null
}
scoped_mode() { [ "${D0:-disconnected}" != disconnected ]; }
note_scoped_once() {
  if [ -z "${SCOPED_NOTED:-}" ] && scoped_mode; then
    info "another agent is connected: creature assertions are scoped to this suite's session"; SCOPED_NOTED=1
  fi
}
mark_done() { LAST_DONE_MARK="$(state_field .lastCompletionAt 2>/dev/null || echo null)"; }
assert_state() { # expected [session-id]
  local actual status deadline want
  if scoped_mode && [ -n "${2:-}" ]; then
    note_scoped_once
    case "$1" in
      idle) want=idle ;; working) want=working ;; needsYou) want=needsConfirmation ;;
      uhoh) want="errored|thinking" ;; done) want=idle ;;
      *) want="$1" ;;
    esac
    deadline=$((SECONDS + 6))
    actual="$(session_state "$2")"; status=$?
    while [ "$status" = 0 ] && [ -n "$actual" ] && ! printf '%s' "$actual" | grep -qE "^(${want})$" && [ "$SECONDS" -lt "$deadline" ]; do
      sleep 0.2; actual="$(session_state "$2")"; status=$?
    done
    if state_field .creature.state >/dev/null 2>&1; then :; elif [ "$?" = 4 ]; then
      info '/state returned 404; skipping creature assertion (non-headless app)'; return; fi
    if [ -n "$actual" ] && printf '%s' "$actual" | grep -qE "^(${want})$"; then
      if [ "$1" = done ]; then
        local now; now="$(state_field .lastCompletionAt 2>/dev/null || echo null)"
        [ "$now" != "${LAST_DONE_MARK:-null}" ] && ok "session $2 done (lastCompletionAt advanced)" || bad "session $2 idle but lastCompletionAt did not advance"
      else ok "session $2 state=$actual"; fi
    else bad "expected session $2 state=$want, got ${actual:-<absent>}"; fi
    return
  fi
  deadline=$((SECONDS + 6))
  actual="$(state_field .creature.state)"; status=$?
  # Phase 1 intentionally lets a short cheer outrank resumed work or idle.
  while [ "$status" = 0 ] && [ "$actual" = done ] &&
      { [ "$1" = working ] || [ "$1" = idle ]; } && [ "$SECONDS" -lt "$deadline" ]; do
    sleep 0.2
    actual="$(state_field .creature.state)"; status=$?
  done
  if [ "$status" = 4 ]; then info '/state returned 404; skipping creature assertion (non-headless app)'
  elif [ "$status" = 0 ] && [ "$actual" = "$1" ]; then ok "creature=$1"
  elif [ "$status" = 0 ] && [ "$1" = done ] && [ "$(state_field .lastCompletionAt 2>/dev/null || echo null)" != "${LAST_DONE_MARK:-null}" ]; then
    # Two completions within the fold window share one cheer (Phase 1 rule);
    # the completion still happened, which lastCompletionAt proves.
    ok "creature=$actual (completion folded into a cheer still playing)"
  else bad "expected creature=$1, got ${actual:-<unavailable>}"; fi
}
recent_has() {
  "${CURL[@]}" --fail --max-time 5 "${AUTH[@]}" "$BASE/diag/recent?n=500" | python3 -c '
import json,sys
entries=json.load(sys.stdin)["entries"]
sys.exit(0 if any(e["source"]==sys.argv[1] and e["event"]==sys.argv[2] and e["timestamp"]>=float(sys.argv[3]) for e in entries) else 1)
' "$1" "$2" "${RECENT_SINCE:-0}"
}
mark_recent() { RECENT_SINCE="$(python3 -c 'import time; print(time.time()*1000)')"; }
assert_recent() {
  if recent_has "$1" "$2"; then ok "received $1/$2"; else bad "missing $1/$2 in recent diagnostics"; fi
}
body_field() { printf '%s' "$1" | python3 -c 'import json,sys; print(json.load(sys.stdin).get(sys.argv[1],sys.argv[2]))' "$2" "${3:-}"; }

post_signal() { "${CURL[@]}" -X POST "${BASE}/hook/signal" "${AUTH[@]}" -H 'Content-Type: application/json' -d "$1" >/dev/null; }
post_event()  { "${CURL[@]}" -X POST "${BASE}/hook/event?source=$1" "${AUTH[@]}" -H 'Content-Type: application/json' -d "$2" >/dev/null; }
approve()     { "${CURL[@]}" --max-time "${3:-5}" -X POST "${BASE}/hook/approve?source=$1" "${AUTH[@]}" -H 'Content-Type: application/json' -d "$2"; }

settle() { sleep 0.3; }

# stateVersion advanced since $1, with label $2
adv()   { local a; a="$(version)"; if [ -n "$a" ] && [ "$a" -gt "${1:-0}" ]; then ok "$2  (v${1}→v${a})"; else bad "$2 — state did not change (v$1→v${a:-?})"; fi; }
# Wait until stateVersion stops moving. Call before capturing the baseline
# for an exact-delta assertion (ev_by): the 2s stale timer bumps the version
# on its own when a celebrate or affection window expires, and an exact-delta
# check can't tell that background bump from the event under test.
quiesce() {
  local a b i
  for i in 1 2 3 4 5 6 7 8; do
    a="$(version)"; sleep 1; b="$(version)"
    [ "$a" = "$b" ] && return 0
  done
  info "state still moving after ${i}s; exact-delta assertion may flake"
}
connected() { [ "$(desktop)" = "connected" ] && ok "${1:-desktop connected}" || bad "${2:-desktop is not connected}"; }
baseline()  { # label [session-id]
  # With /state available, the exact check is "our session is gone"; another
  # agent's live session (e.g. the harness running this script) is not ours.
  local sid="${2:-}" present
  if [ -n "$sid" ] && present="$(state_field .activeSessions 2>/dev/null)"; then
    if printf '%s' "$present" | python3 -c 'import json,sys; sys.exit(0 if any(x.get("id")==sys.argv[1] for x in json.load(sys.stdin)) else 1)' "$sid"; then
      bad "$1 — session $sid still present"
    else
      ok "$1 (session $sid gone)"; info "desktop=$(desktop)"
    fi
    return
  fi
  if [ "${D0:-}" = "disconnected" ]; then
    [ "$(desktop)" = "disconnected" ] && ok "$1" || bad "$1 — desktop still connected (session lingered)"
  else
    info "desktop=$(desktop) (another agent already connected; skipping full-disconnect assertion)"
  fi
}

# post an event / signal and assert stateVersion advanced
ev()  { local b sid; b="$(version)"; sid="$(body_field "$2" session_id)"; mark_recent; mark_done; post_event "$1" "$2"; settle; adv "$b" "$3"; assert_state "$4" "$sid"; assert_recent "$1" "$(body_field "$2" hook_event_name)"; }   # source body label
sig() { local b sid; b="$(version)"; sid="$(body_field "$1" session_id)"; mark_recent; mark_done; post_signal "$1"; settle; adv "$b" "$2"; assert_state "$3" "$sid"; assert_recent "$(body_field "$1" agent_id)" "$(body_field "$1" signal)"; }       # body label

# post an event and assert stateVersion advanced by EXACTLY $3, with
# quiesce + retry. Exact deltas are how a check tells "did only what it
# should" from "did one thing too many" (e.g. the session-liveness touch every
# /hook/event performs is +1; an unwanted card on top would be +2). But
# stateVersion is global: another connected agent's hook traffic or a
# stale-timer expiry can bump it inside the settle window, which on a single
# sample looks exactly like a regression. A real regression is off by the same
# amount on every attempt, so three clean-baseline tries separate signal from
# noise.
ev_by() { # source body delta label
  local i b a
  for i in 1 2 3; do
    quiesce
    b="$(version)"; mark_recent; post_event "$1" "$2"; settle; a="$(version)"
    # ${b} braced before the arrow: macOS bash 3.2 parses the multibyte →
    # into an unbraced variable name, so "$b→" looks up a variable literally
    # named "b→" (an unbound-variable error under set -u).
    if [ "$a" = "$(( b + $3 ))" ]; then ok "$4  (v${b}→v$a, +$3)"; if [ -n "${5:-}" ]; then assert_state "$5" "$(body_field "$2" session_id)"; fi; assert_recent "$1" "$(body_field "$2" hook_event_name)"; return 0; fi
  done
  bad "$4 — expected +$3, got v${b}→v${a:-?} on all 3 attempts"
}
# post an event that must not change state at all (no session touch: the
# session named in it must not exist).
noop_ev() { ev_by "$1" "$2" 0 "$3"; } # source body label

# immediate approval that should return an allow decision quickly
approve_allows() { # src body label
  mark_recent
  local r; r="$(approve "$1" "$2" 5)"
  assert_state working
  assert_recent "$1" auto-allow
  case "$r" in *'"allow"'*) ok "$3: $r" ;; *) bad "$3 — expected an immediate allow, got '${r:-<empty>}'" ;; esac
}

# approval that must BLOCK (not auto-approved), then be resolved by $3 (a shell
# function — typically ending the session), with the final response expected to
# contain $4. Pass __EMPTY__ as $4 to assert an empty response body.
parked_approve() { # src body resolver_fn expect
  local src="$1" body="$2" resolver="$3" expect="$4" out cpid resp
  mark_recent
  out="$(mktemp)"
  "${CURL[@]}" --max-time 20 -X POST "${BASE}/hook/approve?source=${src}" \
    "${AUTH[@]}" -H 'Content-Type: application/json' -d "$body" > "$out" 2>/dev/null &
  cpid=$!
  sleep 0.6
  if [ -s "$out" ]; then bad "approval returned immediately (should have blocked): $(tr -d '\n' < "$out")"
  else ok "approval blocked pending a decision (not auto-approved)"; fi
  assert_state needsYou
  assert_recent "$src" "$(body_field "$body" hook_event_name approve)"
  "$resolver"
  wait "$cpid" 2>/dev/null
  resp="$(tr -d '\n' < "$out")"; rm -f "$out"
  if [ "$expect" = "__EMPTY__" ]; then
    if [ -z "$resp" ]; then ok "blocked approval resolved with empty passthrough body"
    else bad "resolved response expected empty body, got '$resp'"; fi
  else
    case "$resp" in
      *"$expect"*) ok "blocked approval resolved with '$expect': $resp" ;;
      *) bad "resolved response missing '$expect': '${resp:-<empty>}'" ;;
    esac
  fi
}

# A hook whose curl dies mid-wait (agent killed, hook timeout fired) must
# have its card withdrawn: HookServer watches the connection's closeFuture
# and applies the abandonment as a reducer event. Observable over HTTP as
# stateVersion advancing again after the client hangs up, with no new input.
# This is the one approval path unit tests cannot reach — it needs a real
# TCP close against the real server.
abandoned_approve() { # src body
  local src="$1" body="$2" v1 v2 cpid
  mark_recent
  "${CURL[@]}" --max-time 3 -X POST "${BASE}/hook/approve?source=${src}" \
    "${AUTH[@]}" -H 'Content-Type: application/json' -d "$body" >/dev/null 2>&1 &
  cpid=$!
  sleep 0.5
  assert_state needsYou
  assert_recent "$src" "$(body_field "$body" hook_event_name approve)"
  v1="$(version)"           # approvalArrived applied; curl still parked
  wait "$cpid" 2>/dev/null  # curl gives up at 3s — this is the hang-up
  sleep 0.7                 # let the close propagate and the abandon apply
  v2="$(version)"
  if [ -n "$v1" ] && [ -n "$v2" ] && [ "$v2" -gt "$v1" ]; then
    assert_state working
    ok "client hang-up withdrew the parked approval  (v${v1}→v${v2})"
  else
    bad "client hang-up did not change state — card stays up until timeout (v${v1:-?}→v${v2:-?})"
  fi
}

require_app() {
  local h; h="$(health)"
  if [ -z "$h" ]; then
    printf '\033[31m✗ no response from %s/healthz — is the app running?\033[0m\n' "$BASE"
    printf '  Start it with:  (cd app && swift run Boop) &\n'
    exit 1
  fi
  D0="$(desktop)"
  info "baseline: stateVersion=$(version), desktop=${D0}"
  [ "$D0" = "connected" ] && info "(another agent is already connected — disconnect assertions become informational)"
}

print_summary() {
  hdr "Summary"
  printf '  %d passed, %d failed\n' "$pass" "$fail"
  [ -n "${E2E_RESULT_FILE:-}" ] && echo "$pass $fail" > "$E2E_RESULT_FILE"
  [ "$fail" -eq 0 ]
}

# True when any session other than ours is live: a harness running this very
# script hooks itself in mid-run, so scope is decided at assertion time.
foreign_present() { # sid
  state_field .activeSessions | python3 -c 'import json,sys
sys.exit(0 if any(s.get("id")!=sys.argv[1] for s in json.load(sys.stdin)) else 1)' "$1" 2>/dev/null
}
session_field() {
  state_field .activeSessions | python3 -c 'import json,sys
s=next((s for s in json.load(sys.stdin) if s["id"]==sys.argv[1]),{})
for key in sys.argv[2].strip(".").split("."): s=s.get(key,{}) if isinstance(s,dict) else {}
print(s if s != {} and s is not None else "")' "$1" "$2"
}

# Native fixture replay through the real authenticated hook route.
tenth_try() {
  local agent="$1" sid="e2e-tenth-$1-$$" line n=0 got
  GROWTH_BEFORE="$(state_field .growth.xp)"
  hdr "$agent tenth-try"
  local attempts=0 fixture_agent="$agent"
  [ "$agent" = codex ] && fixture_agent=claude-code
  while [ -n "$(state_field .creature.cheer)" ] && [ "$attempts" -lt 100 ]; do
    sleep 0.1
    attempts=$((attempts+1))
  done
  [ -z "$(state_field .creature.cheer)" ] || { bad 'previous cheer did not expire'; return; }
  while IFS= read -r line; do
    post_event "$agent" "$line"
    n=$((n+1))
    if [ "$n" = 12 ]; then
      if scoped_mode || foreign_present "$sid"; then
        got="$(session_field "$sid" effort)"
      else got="$(state_field .creature.effort)"; fi
      [ "$got" = light ] && ok 'tenth-try: short task stays light despite retries' || bad "tenth-try effort: $got"
    fi
  done < <(python3 - "$DIR/../../Tests/Fixtures/hooks/$fixture_agent/2026-09-08/tenth-try.jsonl" "$sid" <<'PY'
import json,sys
for line in open(sys.argv[1]):
    body=json.loads(line)
    body['session_id']=sys.argv[2]
    if 'conversation_id' in body: body['conversation_id']=sys.argv[2]
    print(json.dumps(body,separators=(',',':')))
PY
  )
  if scoped_mode || foreign_present "$sid"; then
    got="$(session_field "$sid" cheer)"
  else got="$(state_field .creature.cheer)"; fi
  [ "$got" = hop ] && ok 'tenth-try: duration-only hop' || bad "tenth-try payoff: $got"
  post_event "$agent" "{\"hook_event_name\":\"SessionEnd\",\"session_id\":\"$sid\"}"
}

# Verify the durable growth result after tenth_try has completed.
growth_check() {
  local xp level expected
  xp="$(state_field .growth.xp)"; level="$(state_field .growth.level)"
  if [ -n "$xp" ] && [ "$xp" -gt "${GROWTH_BEFORE:-0}" ]; then ok 'growth XP increased after tenth-try'; else bad 'growth XP did not increase'; fi
  expected="$(python3 - "$xp" <<'PYCODE'
import sys
xp=int(sys.argv[1]); level=1
while 100*level*(level+1)//2+50*level <= xp: level+=1
print(level)
PYCODE
  )"
  [ "$level" = "$expected" ] && ok "growth level matches curve ($level)" || bad "growth level $level != $expected"
}
