#!/usr/bin/env bash
#
# Cursor e2e suite — POST /hook/signal + POST /hook/approve (source=cursor).
# Cursor identifies sessions by conversation_id and routes shell/MCP approvals
# through the legacy passthrough endpoint when old hooks remain. Run standalone or via
# ../e2e-smoke.sh.

set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"

require_app
CU="e2e-cursor-conv-$$"   # Cursor's conversation_id

hdr "Cursor  →  POST /hook/signal  (lifecycle: the four mapped signals)"
sig "{\"agent_id\":\"cursor\",\"signal\":\"start_working\",\"session_id\":\"$CU\",\"cwd\":\"$CWD\"}" "start_working (sessionStart/beforeSubmitPrompt) → busy/connected" working
connected
sig "{\"agent_id\":\"cursor\",\"signal\":\"keep_working\",\"session_id\":\"$CU\",\"cwd\":\"$CWD\"}"  "keep_working (after*Execution) → busy" working
sig "{\"agent_id\":\"cursor\",\"signal\":\"stop_working\",\"session_id\":\"$CU\"}"                   "stop_working (stop) → done" done
sig "{\"agent_id\":\"cursor\",\"signal\":\"start_working\",\"session_id\":\"$CU\",\"cwd\":\"$CWD\"}" "start_working (resume) → busy" working

hdr "Cursor → legacy approvals always remain native"
passthrough_approve cursor "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"/tmp/x\"},\"conversation_id\":\"$CU\"}" "read-only tool remains native"
passthrough_approve cursor "{\"command\":\"git status\",\"conversation_id\":\"$CU\"}" "shell remains native"
passthrough_approve cursor "{\"command\":\"git status && echo chained\",\"conversation_id\":\"$CU\"}" "chained shell remains native"
post_signal "{\"agent_id\":\"cursor\",\"signal\":\"session_end\",\"session_id\":\"$CU\"}"

settle
baseline "Cursor session reaped" "$CU"

tenth_try cursor
growth_check

print_summary
