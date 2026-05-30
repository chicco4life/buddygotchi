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
ev claude-code "{\"hook_event_name\":\"SessionStart\",\"session_id\":\"$CC\",\"cwd\":\"$CWD\"}" "SessionStart → registered (idle)"
connected
ev claude-code "{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"$CC\"}"             "UserPromptSubmit → busy"
ev claude-code "{\"hook_event_name\":\"PostToolUse\",\"session_id\":\"$CC\"}"                  "PostToolUse → keep busy"
ev claude-code "{\"hook_event_name\":\"Stop\",\"session_id\":\"$CC\"}"                         "Stop → celebrate"
ev claude-code "{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"$CC\"}"             "UserPromptSubmit (next turn) → busy"
ev claude-code "{\"hook_event_name\":\"StopFailure\",\"session_id\":\"$CC\"}"                  "StopFailure → idle"

hdr "Claude Code  →  notifications, permission card, elicitation (passive)"
ev claude-code "{\"hook_event_name\":\"Notification\",\"notification_type\":\"idle_prompt\",\"session_id\":\"$CC\"}"                                      "Notification:idle_prompt → idle/stop"
ev claude-code "{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"$CC\"}"                                                                       "UserPromptSubmit → busy"
ev claude-code "{\"hook_event_name\":\"PermissionRequest\",\"session_id\":\"$CC\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"rm -rf build\"}}" "PermissionRequest → attention (passive tool card)"
ev claude-code "{\"hook_event_name\":\"PostToolUse\",\"session_id\":\"$CC\"}"                                                                            "PostToolUse → clears card, busy"
ev claude-code "{\"hook_event_name\":\"Notification\",\"notification_type\":\"permission_prompt\",\"message\":\"Allow?\",\"session_id\":\"$CC\"}"          "Notification:permission_prompt → attention (skipped if Local Approval Mode on)"
ev claude-code "{\"hook_event_name\":\"Notification\",\"notification_type\":\"elicitation_dialog\",\"message\":\"Pick one\",\"session_id\":\"$CC\"}"       "Notification:elicitation_dialog → attention"
ev claude-code "{\"hook_event_name\":\"Elicitation\",\"message\":\"Provide a value\",\"session_id\":\"$CC\"}"                                             "Elicitation → attention"
ev claude-code "{\"hook_event_name\":\"ElicitationResult\",\"session_id\":\"$CC\"}"                                                                      "ElicitationResult → clears, busy"

hdr "Claude Code  →  POST /hook/approve  (blocking; resolved by session death = fail-open allow)"
resolve_cc() { post_event claude-code "{\"hook_event_name\":\"SessionEnd\",\"session_id\":\"$CC\"}"; }
parked_approve claude-code \
  "{\"hook_event_name\":\"PermissionRequest\",\"session_id\":\"$CC\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git push --force\"}}" \
  resolve_cc '"behavior":"allow"'
settle
baseline "Claude Code session reaped"

print_summary
