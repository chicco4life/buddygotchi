#!/usr/bin/env bash
#
# Shared helpers for the Boop e2e suites. Source this from each client
# script; it provides the HTTP plumbing, assertions, and summary.
#
# What's observable over HTTP (and therefore assertable):
#   • GET /healthz          → { ok, stateVersion, desktop }   (no pet/prompt/counts)
#   • POST /hook/event      → 200, advances stateVersion
#   • POST /hook/signal     → 200, advances stateVersion
#   • POST /hook/approve     → returns the decision JSON (richly assertable)
# Pet state (busy/attention/celebrate) is NOT exposed, so those steps assert
# "the event was accepted and changed state" (stateVersion advanced) and print
# the expected pet state as info.

PORT="${BUDDY_PORT:-21321}"
BASE="http://127.0.0.1:${PORT}"
CURL=(curl -s --noproxy '*' --connect-timeout 2)
TOKEN="$(grep -o '"token" *: *"[^"]*"' "$HOME/.boop/config.json" 2>/dev/null | head -1 | sed 's/.*"token" *: *"//; s/".*//')"
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

post_signal() { "${CURL[@]}" -X POST "${BASE}/hook/signal" "${AUTH[@]}" -H 'Content-Type: application/json' -d "$1" >/dev/null; }
post_event()  { "${CURL[@]}" -X POST "${BASE}/hook/event?source=$1" "${AUTH[@]}" -H 'Content-Type: application/json' -d "$2" >/dev/null; }
approve()     { "${CURL[@]}" --max-time "${3:-5}" -X POST "${BASE}/hook/approve?source=$1" "${AUTH[@]}" -H 'Content-Type: application/json' -d "$2"; }

settle() { sleep 0.3; }

# stateVersion advanced since $1, with label $2
adv()   { local a; a="$(version)"; if [ -n "$a" ] && [ "$a" -gt "${1:-0}" ]; then ok "$2  (v$1→v$a)"; else bad "$2 — state did not change (v$1→v${a:-?})"; fi; }
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
baseline()  { # label
  if [ "${D0:-}" = "disconnected" ]; then
    [ "$(desktop)" = "disconnected" ] && ok "$1" || bad "$1 — desktop still connected (session lingered)"
  else
    info "desktop=$(desktop) (another agent already connected; skipping full-disconnect assertion)"
  fi
}

# post an event / signal and assert stateVersion advanced
ev()  { local b; b="$(version)"; post_event "$1" "$2"; settle; adv "$b" "$3"; }   # source body label
sig() { local b; b="$(version)"; post_signal "$1"; settle; adv "$b" "$2"; }       # body label

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
    b="$(version)"; post_event "$1" "$2"; settle; a="$(version)"
    if [ "$a" = "$(( b + $3 ))" ]; then ok "$4  (v$b→v$a, +$3)"; return 0; fi
  done
  bad "$4 — expected +$3, got v$b→v${a:-?} on all 3 attempts"
}
# post an event that must not change state at all (no session touch: the
# session named in it must not exist).
noop_ev() { ev_by "$1" "$2" 0 "$3"; } # source body label

# immediate approval that should return an allow decision quickly
approve_allows() { # src body label
  local r; r="$(approve "$1" "$2" 5)"
  case "$r" in *'"allow"'*) ok "$3: $r" ;; *) bad "$3 — expected an immediate allow, got '${r:-<empty>}'" ;; esac
}

# approval that must BLOCK (not auto-approved), then be resolved by $3 (a shell
# function — typically ending the session), with the final response expected to
# contain $4. Pass __EMPTY__ as $4 to assert an empty response body.
parked_approve() { # src body resolver_fn expect
  local src="$1" body="$2" resolver="$3" expect="$4" out cpid resp
  out="$(mktemp)"
  "${CURL[@]}" --max-time 20 -X POST "${BASE}/hook/approve?source=${src}" \
    "${AUTH[@]}" -H 'Content-Type: application/json' -d "$body" > "$out" 2>/dev/null &
  cpid=$!
  sleep 0.6
  if [ -s "$out" ]; then bad "approval returned immediately (should have blocked): $(tr -d '\n' < "$out")"
  else ok "approval blocked pending a decision (not auto-approved)"; fi
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
