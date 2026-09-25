#!/bin/bash
# Runs the unattended Boop v1 build: one fresh Claude Code session per
# iteration, following plan/LOOP.md, until plan/evidence/v1-build/DONE exists.
# Survives usage limits by waiting and retrying. See plan/PLAN.md §5.
#
# Usage, from the repo root:
#   caffeinate -dimsu tools/build-loop.sh
#
# Tunables (environment variables): MAX_ITERATIONS, PAUSE_OK, PAUSE_FAIL,
# MAX_FAIL_WAIT, MAX_IDLE, ITERATION_TIMEOUT, BOOP_LOOP_LOGS.
set -u
cd "$(dirname "$0")/.." || exit 1

done_file=plan/evidence/v1-build/DONE
prompt_file=plan/LOOP.md
log_dir=${BOOP_LOOP_LOGS:-/tmp/boop-build-loop}
max_iterations=${MAX_ITERATIONS:-80}
pause_ok=${PAUSE_OK:-20}               # seconds between successful iterations
pause_fail=${PAUSE_FAIL:-900}          # seconds to wait after a failure or usage limit
max_fail_wait=${MAX_FAIL_WAIT:-28800}  # give up after failing this long in a row (8 h)
max_idle=${MAX_IDLE:-3}                # stop after this many clean iterations with no commit
iteration_timeout=${ITERATION_TIMEOUT:-9000}  # hard cap per iteration (2.5 h)

mkdir -p "$log_dir"
iteration=0
failing_since=0
idle=0

note() { printf '%s  %s\n' "$(date '+%F %T')" "$*" | tee -a "$log_dir/loop.log"; }

while [ ! -f "$done_file" ]; do
  if [ "$iteration" -ge "$max_iterations" ]; then
    note "stopping: reached $max_iterations iterations"
    exit 1
  fi
  iteration=$((iteration + 1))
  log=$(printf '%s/iteration-%03d.log' "$log_dir" "$iteration")
  head_before=$(git rev-parse HEAD 2>/dev/null)
  note "iteration $iteration → $log"

  # perl's alarm gives the iteration a hard time limit (macOS has no `timeout`).
  perl -e 'alarm shift; exec @ARGV' "$iteration_timeout" \
    claude -p "$(cat "$prompt_file")" \
      --permission-mode auto --permission-prompts none \
      >"$log" 2>&1
  code=$?
  head_after=$(git rev-parse HEAD 2>/dev/null)

  # A clean exit with no commit may still be a usage limit; only then trust
  # the log text, so an iteration that merely mentions limits isn't misread.
  limited=0
  if [ "$code" -eq 0 ] && [ "$head_after" = "$head_before" ] &&
     grep -qiE "usage limit|rate limit|limit reached|resets at|overloaded" "$log"; then
    limited=1
  fi

  if [ "$code" -eq 0 ] && [ "$limited" -eq 0 ]; then
    failing_since=0
    if [ "$head_after" = "$head_before" ]; then
      idle=$((idle + 1))
      note "iteration $iteration made no new commit ($idle in a row)"
      if [ "$idle" -ge "$max_idle" ]; then
        note "stopping: no progress in $idle iterations; see $log"
        exit 1
      fi
    else
      idle=0
    fi
    sleep "$pause_ok"
  else
    now=$(date +%s)
    [ "$failing_since" -eq 0 ] && failing_since=$now
    note "iteration $iteration ended with exit $code (usage limit: $limited); retrying in $((pause_fail / 60)) min"
    tail -n 3 "$log" | sed 's/^/    /' | tee -a "$log_dir/loop.log"
    if [ $((now - failing_since)) -ge "$max_fail_wait" ]; then
      note "stopping: failing for $(((now - failing_since) / 60)) min"
      exit 1
    fi
    sleep "$pause_fail"
  fi
done

note "done: $done_file exists"
