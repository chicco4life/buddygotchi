/**
 * Codex input adapter (stub).
 */

import { BaseHookInput } from "./base.js";

export class CodexInput extends BaseHookInput {
  readonly agentId = "codex";
  protected readonly requestIdPrefix = "codex_";
}
