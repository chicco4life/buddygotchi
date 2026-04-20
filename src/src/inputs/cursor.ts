/**
 * Cursor input adapter.
 *
 * Handles POST /hook/cursor from the Cursor PreToolUse hook.
 * Response format: {"decision": "allow" | "deny" | "ask"}
 */

import { BaseHookInput } from "./base.js";

export class CursorInput extends BaseHookInput {
  readonly agentId = "cursor";
  protected readonly requestIdPrefix = "cursor_";
}
