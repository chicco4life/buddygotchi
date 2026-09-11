#!/usr/bin/env bash
#
# Claude Code e2e suite — POST /hook/event (source=claude-code).
# Covers every event handleAgentEvent recognizes for Claude Code, plus the
# legacy /hook/approve passthrough. Run standalone or via ../e2e-smoke.sh.

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
ev claude-code "{\"hook_event_name\":\"Stop\",\"session_id\":\"$CC\"}"                         "Stop → completed turn" done
ev claude-code "{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"$CC\"}"             "UserPromptSubmit (next turn) → busy" working
ev claude-code "{\"hook_event_name\":\"StopFailure\",\"session_id\":\"$CC\"}"                  "StopFailure → uhoh" uhoh

hdr "Claude Code  →  notifications, native permissions, elicitation (passive)"
ev claude-code "{\"hook_event_name\":\"Notification\",\"notification_type\":\"idle_prompt\",\"session_id\":\"$CC\"}"                                      "Notification:idle_prompt → done" done
ev claude-code "{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"$CC\"}"                                                                       "UserPromptSubmit → busy" working
ev_by claude-code "{\"hook_event_name\":\"PermissionRequest\",\"session_id\":\"$CC\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"rm -rf build\"}}" 0 "PermissionRequest remains in the editor" working
ev claude-code "{\"hook_event_name\":\"PostToolUse\",\"session_id\":\"$CC\"}"                                                                            "PostToolUse → clears card, busy" working
# +1 is the session-liveness touch every /hook/event performs; a raised card
# would add a second bump (requestArrived). native permissions do not create cards.
ev_by claude-code "{\"hook_event_name\":\"Notification\",\"notification_type\":\"permission_prompt\",\"message\":\"Allow?\",\"session_id\":\"$CC\"}" 1 "Notification:permission_prompt → ignored beyond liveness touch (native permissions do not create cards)" working
ev claude-code "{\"hook_event_name\":\"Notification\",\"notification_type\":\"elicitation_dialog\",\"message\":\"Pick one\",\"session_id\":\"$CC\"}"       "Notification:elicitation_dialog → attention" needsYou
ev claude-code "{\"hook_event_name\":\"Elicitation\",\"message\":\"Provide a value\",\"session_id\":\"$CC\"}"                                             "Elicitation → attention" needsYou
ev claude-code "{\"hook_event_name\":\"ElicitationResult\",\"session_id\":\"$CC\"}"                                                                      "ElicitationResult → clears, busy" working

hdr "claude-code → legacy approval passthrough"
passthrough_approve claude-code \
  "{\"hook_event_name\":\"PermissionRequest\",\"session_id\":\"$CC\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git push --force\"}}" \
  "stale approval endpoint returns immediately"
post_event claude-code "{\"hook_event_name\":\"SessionEnd\",\"session_id\":\"$CC\"}"

settle
baseline "Claude Code session reaped" "$CC"

tenth_try claude-code
growth_check

print_summary
