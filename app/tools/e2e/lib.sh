#!/usr/bin/env bash
#
# Shared helpers for the Buddygotchi e2e suites. Source this from each client
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
CWD="${BUDDY_E2E_CWD:-/tmp/buddy-e2e}"

pass=0; fail=0
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$1"; fail=$((fail+1)); }
info() { printf '  \033[2m·\033[0m %s\n' "$1"; }
hdr()  { printf '\n\033[1m%s\033[0m\n' "$1"; }

health()  { "${CURL[@]}" "${BASE}/healthz"; }
version() { health | grep -o '"stateVersion":[0-9]*' | grep -o '[0-9]*'; }
desktop() { health | grep -o '"desktop":"[a-z]*"' | sed 's/.*"desktop":"//; s/"//'; }

post_signal() { "${CURL[@]}" -X POST "${BASE}/hook/signal" -H 'Content-Type: application/json' -d "$1" >/dev/null; }
post_event()  { "${CURL[@]}" -X POST "${BASE}/hook/event?source=$1" -H 'Content-Type: application/json' -d "$2" >/dev/null; }
approve()     { "${CURL[@]}" --max-time "${3:-5}" -X POST "${BASE}/hook/approve?source=$1" -H 'Content-Type: application/json' -d "$2"; }

settle() { sleep 0.3; }

# stateVersion advanced since $1, with label $2
adv()   { local a; a="$(version)"; if [ -n "$a" ] && [ "$a" -gt "${1:-0}" ]; then ok "$2  (v$1→v$a)"; else bad "$2 — state did not change (v$1→v${a:-?})"; fi; }
# stateVersion unchanged since $1 (no-op assertion)
noadv() { local a; a="$(version)"; if [ "$a" = "$1" ]; then ok "$2  (v$1 unchanged)"; else bad "$2 — version changed unexpectedly (v$1→v$a)"; fi; }
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

# immediate approval that should return an allow decision quickly
approve_allows() { # src body label
  local r; r="$(approve "$1" "$2" 5)"
  case "$r" in *'"allow"'*) ok "$3: $r" ;; *) bad "$3 — expected an immediate allow, got '${r:-<empty>}'" ;; esac
}

# approval that must BLOCK (not auto-approved), then be resolved by $3 (a shell
# function — typically ending the session), with the final response expected to
# contain $4. Also verifies the fail-open invariant: a session dying mid-approval
# resolves the hook to "allow".
parked_approve() { # src body resolver_fn expect
  local src="$1" body="$2" resolver="$3" expect="$4" out cpid resp
  out="$(mktemp)"
  "${CURL[@]}" --max-time 20 -X POST "${BASE}/hook/approve?source=${src}" \
    -H 'Content-Type: application/json' -d "$body" > "$out" 2>/dev/null &
  cpid=$!
  sleep 0.6
  if [ -s "$out" ]; then bad "approval returned immediately (should have blocked): $(tr -d '\n' < "$out")"
  else ok "approval blocked pending a decision (not auto-approved)"; fi
  "$resolver"
  wait "$cpid" 2>/dev/null
  resp="$(tr -d '\n' < "$out")"; rm -f "$out"
  case "$resp" in
    *"$expect"*) ok "blocked approval resolved (fail-open) with '$expect': $resp" ;;
    *) bad "resolved response missing '$expect': '${resp:-<empty>}'" ;;
  esac
}

require_app() {
  local h; h="$(health)"
  if [ -z "$h" ]; then
    printf '\033[31m✗ no response from %s/healthz — is the app running?\033[0m\n' "$BASE"
    printf '  Start it with:  (cd app && swift run Buddygotchi) &\n'
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
