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
ev codex "{\"hook_event_name\":\"SessionStart\",\"session_id\":\"$CX\",\"cwd\":\"$CWD\"}"                                            "SessionStart → registered (idle)"
connected
ev codex "{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"$CX\"}"                                                         "UserPromptSubmit → busy"
ev codex "{\"hook_event_name\":\"PreToolUse\",\"session_id\":\"$CX\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls\"}}"     "PreToolUse → busy  (Fix 10: previously left idle)"
ev codex "{\"hook_event_name\":\"PermissionRequest\",\"session_id\":\"$CX\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git commit\"}}" "PermissionRequest → attention (passive tool card)"
ev codex "{\"hook_event_name\":\"PostToolUse\",\"session_id\":\"$CX\"}"                                                              "PostToolUse → clears card, busy"
ev codex "{\"hook_event_name\":\"Stop\",\"session_id\":\"$CX\"}"                                                                     "Stop → celebrate"

hdr "Codex  →  POST /hook/approve  (blocking; resolved by session death = fail-open allow)"
resolve_cx() { post_event codex "{\"hook_event_name\":\"SessionEnd\",\"session_id\":\"$CX\"}"; }   # cleanup; Codex normally relies on the process watcher
parked_approve codex \
  "{\"hook_event_name\":\"PermissionRequest\",\"session_id\":\"$CX\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"rm -rf /\"}}" \
  resolve_cx '"behavior":"allow"'
settle
baseline "Codex session reaped"

print_summary
