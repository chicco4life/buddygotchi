#!/usr/bin/env bash
#
# Codex e2e suite — POST /hook/event (source=codex).
# Codex shares the /hook/event handler with Claude Code but installs a different
# event set (incl. PreToolUse). Run standalone or via ../e2e-smoke.sh.

set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"

require_app
CX="e2e-codex-$$"

hdr "Codex  →  POST /hook/event  (lifecycle)"
ev codex "{\"hook_event_name\":\"SessionStart\",\"session_id\":\"$CX\",\"cwd\":\"$CWD\"}"                                            "SessionStart → registered (idle)" idle
connected
ev codex "{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"$CX\"}"                                                         "UserPromptSubmit → busy" working
ev codex "{\"hook_event_name\":\"PreToolUse\",\"session_id\":\"$CX\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls\"}}"     "PreToolUse → busy  (Fix 10: previously left idle)" working
ev_by codex "{\"hook_event_name\":\"PermissionRequest\",\"session_id\":\"$CX\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git commit\"}}" 0 "PermissionRequest remains in the editor" working
ev codex "{\"hook_event_name\":\"PostToolUse\",\"session_id\":\"$CX\"}"                                                              "PostToolUse → clears card, busy" working
ev codex "{\"hook_event_name\":\"Stop\",\"session_id\":\"$CX\"}"                                                                     "Stop → completed turn" done

hdr "codex → legacy approval passthrough"
passthrough_approve codex \
  "{\"hook_event_name\":\"PermissionRequest\",\"session_id\":\"$CX\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git push --force\"}}" \
  "stale approval endpoint returns immediately"
post_event codex "{\"hook_event_name\":\"SessionEnd\",\"session_id\":\"$CX\"}"

settle
baseline "Codex session reaped" "$CX"

tenth_try codex
growth_check

print_summary
