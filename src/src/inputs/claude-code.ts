/**
 * Claude Code input adapter.
 *
 * Handles POST /hook/claude-code from the Claude Code PreToolUse hook.
 * Response format: {"decision": "allow" | "deny" | "ask"}
 *
 * Note: the actual Claude Code envelope formatting
 * ({"hookSpecificOutput": {"permissionDecision": ...}}) is handled by
 * the CLI hook binary (src/cli/hook.ts), not here. The daemon always
 * returns the generic {decision} shape.
 */

import { BaseHookInput } from "./base.js";

export class ClaudeCodeInput extends BaseHookInput {
  readonly agentId = "claude-code";
  protected readonly requestIdPrefix = "cc_";
}
