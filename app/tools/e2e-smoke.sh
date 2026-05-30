#!/usr/bin/env bash
#
# Buddygotchi end-to-end smoke test — MASTER runner.
#
# Runs the core HTTP contract checks, then each per-agent suite
# (app/tools/e2e/{claude,codex,cursor}.sh) and reports a combined result.
# Run it in your own terminal (it needs real localhost network access):
#
#     app/tools/e2e-smoke.sh
#
# Start the app first if it isn't already running:
#
#     (cd app && swift run Buddygotchi) &
#
# Run a single agent's suite directly, e.g.:
#
#     app/tools/e2e/cursor.sh
#
# For the cleanest disconnect assertions, run with no other agents connected.
#
# Not observable over HTTP (covered by the Swift unit tests instead): pet-state
# priority/aggregation across sessions, session counts, the DENY decision format
# (needs the popover/BLE), the SessionStart process-watcher reap, and the BLE
# output path.

set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
E2E="$DIR/e2e"
# shellcheck source=e2e/lib.sh
source "$E2E/lib.sh"

printf '\033[1m═══ Buddygotchi E2E smoke ═══\033[0m\n'
require_app

# ── Core HTTP contract ───────────────────────────────────────────────────────
hdr "Core contract"
H="$(health)"
case "$H" in *'"ok":true'*)        ok "/healthz reports ok:true" ;;        *) bad "/healthz missing ok:true ($H)" ;; esac
case "$H" in *'"stateVersion"'*)   ok "/healthz exposes stateVersion" ;;   *) bad "/healthz missing stateVersion ($H)" ;; esac
case "$H" in *'"desktop"'*)        ok "/healthz exposes desktop status" ;; *) bad "/healthz missing desktop ($H)" ;; esac
GB="$(version)"
post_event claude-code "{\"hook_event_name\":\"SessionEnd\",\"session_id\":\"ghost-$$\"}"; settle
noadv "$GB" "SessionEnd for a nonexistent session is a no-op"

core_pass=$pass; core_fail=$fail
total_pass=$pass; total_fail=$fail

# ── Per-agent suites ─────────────────────────────────────────────────────────
declare -a SUITES=("Claude Code:claude.sh" "Codex:codex.sh" "Cursor:cursor.sh")
declare -a STATUS=()

for entry in "${SUITES[@]}"; do
  name="${entry%%:*}"; script="${entry##*:}"
  printf '\n\033[1m──────── %s (e2e/%s) ────────\033[0m\n' "$name" "$script"
  rf="$(mktemp)"
  E2E_RESULT_FILE="$rf" bash "$E2E/$script"
  rc=$?
  sp=0; sf=0; read -r sp sf < "$rf" 2>/dev/null || true
  rm -f "$rf"
  total_pass=$((total_pass + sp)); total_fail=$((total_fail + sf))
  if [ "$rc" -eq 0 ]; then STATUS+=("\033[32m✓\033[0m ${name}: ${sp} passed")
  else STATUS+=("\033[31m✗\033[0m ${name}: ${sf} failed, ${sp} passed"); fi
done

# ── Grand summary ────────────────────────────────────────────────────────────
printf '\n\033[1m═══ Master summary ═══\033[0m\n'
printf '  %b Core contract: %d passed, %d failed\n' \
  "$( [ "$core_fail" -eq 0 ] && printf '\033[32m✓\033[0m' || printf '\033[31m✗\033[0m' )" "$core_pass" "$core_fail"
for s in "${STATUS[@]}"; do printf '  %b\n' "$s"; done
printf '\n  Grand total: %d passed, %d failed\n\n' "$total_pass" "$total_fail"
[ "$total_fail" -eq 0 ]
