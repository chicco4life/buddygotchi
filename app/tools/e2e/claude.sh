#!/usr/bin/env bash
#
# Claude Code e2e suite — POST /hook/event (source=claude-code).
# Covers every event handleAgentEvent recognizes for Claude Code, plus the
# blocking /hook/approve round-trip. Run standalone or via ../e2e-smoke.sh.

set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"

require_app
CC="e2e-claude-$$"

hdr "Claude Code  →  POST /hook/event  (lifecycle)"
ev claude-code "{\"hook_event_name\":\"SessionStart\",\"session_id\":\"$CC\",\"cwd\":\"$CWD\"}" "SessionStart → registered (idle)" idle
connected
ev claude-code "{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"$CC\"}"             "UserPromptSubmit → busy" working
ev claude-code "{\"hook_event_name\":\"PostToolUse\",\"session_id\":\"$CC\"}"                  "PostToolUse → keep busy" working
ev claude-code "{\"hook_event_name\":\"Stop\",\"session_id\":\"$CC\"}"                         "Stop → celebrate" done
ev claude-code "{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"$CC\"}"             "UserPromptSubmit (next turn) → busy" working
ev claude-code "{\"hook_event_name\":\"StopFailure\",\"session_id\":\"$CC\"}"                  "StopFailure → uhoh" uhoh

hdr "Claude Code  →  notifications, permission card, elicitation (passive)"
ev claude-code "{\"hook_event_name\":\"Notification\",\"notification_type\":\"idle_prompt\",\"session_id\":\"$CC\"}"                                      "Notification:idle_prompt → done" done
ev claude-code "{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"$CC\"}"                                                                       "UserPromptSubmit → busy" working
ev claude-code "{\"hook_event_name\":\"PermissionRequest\",\"session_id\":\"$CC\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"rm -rf build\"}}" "PermissionRequest → attention (passive tool card)" needsYou
ev claude-code "{\"hook_event_name\":\"PostToolUse\",\"session_id\":\"$CC\"}"                                                                            "PostToolUse → clears card, busy" working
# +1 is the session-liveness touch every /hook/event performs; a raised card
# would add a second bump (requestArrived). PermissionRequest is authoritative.
ev_by claude-code "{\"hook_event_name\":\"Notification\",\"notification_type\":\"permission_prompt\",\"message\":\"Allow?\",\"session_id\":\"$CC\"}" 1 "Notification:permission_prompt → ignored beyond liveness touch (PermissionRequest is authoritative)" working
ev claude-code "{\"hook_event_name\":\"Notification\",\"notification_type\":\"elicitation_dialog\",\"message\":\"Pick one\",\"session_id\":\"$CC\"}"       "Notification:elicitation_dialog → attention" needsYou
ev claude-code "{\"hook_event_name\":\"Elicitation\",\"message\":\"Provide a value\",\"session_id\":\"$CC\"}"                                             "Elicitation → attention" needsYou
ev claude-code "{\"hook_event_name\":\"ElicitationResult\",\"session_id\":\"$CC\"}"                                                                      "ElicitationResult → clears, busy" working

hdr "Claude Code  →  POST /hook/approve  (client hang-up = abandonment)"
abandoned_approve claude-code \
  "{\"hook_event_name\":\"PermissionRequest\",\"session_id\":\"${CC}-gone\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"sleep 999\"}}"
post_event claude-code "{\"hook_event_name\":\"SessionEnd\",\"session_id\":\"${CC}-gone\"}"

hdr "Claude Code  →  POST /hook/approve  (blocking; resolved by session death = passthrough)"
resolve_cc() { post_event claude-code "{\"hook_event_name\":\"SessionEnd\",\"session_id\":\"$CC\"}"; }
parked_approve claude-code \
  "{\"hook_event_name\":\"PermissionRequest\",\"session_id\":\"$CC\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git push --force\"}}" \
  resolve_cc __EMPTY__
settle
baseline "Claude Code session reaped" "$CC"

print_summary
