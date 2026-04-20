/**
 * Input layer base types and shared hook input logic.
 */

import { randomUUID } from "crypto";
import type { Engine } from "../core/engine.js";

export interface ToolApprovalRequest {
  requestId: string;
  agentId: string;
  tool: string;
  hint: string;
  source: string;
  timeoutS: number;
}

export interface InputProvider {
  readonly agentId: string;
  start(engine: Engine): Promise<void>;
  stop(): Promise<void>;
  handleRequest(body: Record<string, unknown>): Promise<Response>;
}

/** Map engine decision to hook HTTP response vocabulary. */
export function mapDecision(decision: string): "allow" | "deny" | "ask" {
  if (decision === "approve") return "allow";
  if (decision === "deny") return "deny";
  return "ask";
}

export function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

/**
 * Base class for hook-based input adapters.
 *
 * Subclasses only need to set `agentId` and `requestIdPrefix`.
 * The shared logic handles: start/stop lifecycle, idle heartbeat,
 * request parsing, submit-and-await with timeout, and cleanup.
 */
export abstract class BaseHookInput implements InputProvider {
  abstract readonly agentId: string;
  protected abstract readonly requestIdPrefix: string;

  protected _engine: Engine | null = null;
  private _idleTimer: ReturnType<typeof setInterval> | null = null;

  async start(engine: Engine): Promise<void> {
    this._engine = engine;
    engine.agentConnected(this.agentId);
    this._idleTimer = setInterval(() => {
      engine.agentConnected(this.agentId);
    }, 5000);
  }

  async stop(): Promise<void> {
    if (this._idleTimer) {
      clearInterval(this._idleTimer);
      this._idleTimer = null;
    }
    if (this._engine) {
      this._engine.agentDisconnected(this.agentId);
    }
  }

  async handleRequest(body: Record<string, unknown>): Promise<Response> {
    if (!this._engine) {
      return jsonResponse({ decision: "ask" }, 503);
    }

    const tool = typeof body.tool === "string" ? body.tool : "";
    const hint = typeof body.hint === "string" ? body.hint : "";
    const source = typeof body.source === "string" ? body.source : this.agentId;
    const timeoutS = typeof body.timeout_s === "number" ? body.timeout_s : 30;

    if (!tool) {
      return jsonResponse({ error: "missing_tool" }, 400);
    }

    const requestId = `${this.requestIdPrefix}${randomUUID().replace(/-/g, "").slice(0, 12)}`;
    const decision = await this._submitAndAwait({
      requestId,
      agentId: this.agentId,
      tool,
      hint,
      source,
      timeoutS,
    });

    return jsonResponse({ decision: mapDecision(decision) });
  }

  private async _submitAndAwait(req: ToolApprovalRequest): Promise<string> {
    const engine = this._engine!;
    let timeoutHandle: ReturnType<typeof setTimeout>;

    const promise = new Promise<string>((resolve) => {
      engine.registerPending(req.requestId, resolve);
    });

    engine.submitRequest({
      requestId: req.requestId,
      agentId: req.agentId,
      tool: req.tool,
      hint: req.hint,
      source: req.source,
    });

    const timeoutPromise = new Promise<string>((resolve) => {
      timeoutHandle = setTimeout(() => {
        engine.expireRequest(req.requestId);
        resolve("ask");
      }, req.timeoutS * 1000);
    });

    const decision = await Promise.race([promise, timeoutPromise]);
    clearTimeout(timeoutHandle!);

    if (decision !== "ask") {
      engine.clearRequest(req.requestId);
    }
    return decision;
  }
}
