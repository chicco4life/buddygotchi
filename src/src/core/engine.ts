/**
 * Engine: the core orchestrator.
 *
 * Replaces Bridge from the Python codebase. Connects input providers
 * (agent adapters) and output providers (display targets) through a
 * pure reducer. The Engine never knows about specific agents or outputs.
 *
 * Key difference from Bridge: the Engine never calls upstream.send().
 * Instead, when a decision arrives, it resolves the asyncio Future
 * (here: a Promise resolver) that the input provider registered.
 */

import type { Config } from "./config.js";
import type { ErrorCode } from "./errors.js";
import type { Event } from "./events.js";
import type { ActivitySignalKind } from "./events.js";
import { type InternalState, INITIAL_STATE, reduce } from "./state.js";
import type { BuddyState } from "../../schema/state.js";

export type StateListener = (prev: BuddyState, next: BuddyState) => void;
type PendingResolve = (decision: string) => void;

export class Engine {
  private _state: InternalState;
  private _listeners = new Set<StateListener>();
  private _pending = new Map<string, PendingResolve>();
  private _clientLastDecide = new Map<string, number>();
  private _staleTimer: ReturnType<typeof setInterval> | null = null;
  private _config: Config;

  constructor(config: Config) {
    this._config = config;
    this._state = { ...INITIAL_STATE, staleMs: config.staleTimeoutMs };
  }

  // --- Lifecycle -----------------------------------------------------------

  start(): void {
    this._staleTimer = setInterval(() => {
      this._pruneClientRateLimit();
      this._apply({ type: "stale_tick", at: Date.now() });
    }, 2000);
  }

  stop(): void {
    if (this._staleTimer) {
      clearInterval(this._staleTimer);
      this._staleTimer = null;
    }
    // Resolve any pending requests so hook scripts don't hang.
    for (const [id, resolve] of this._pending) {
      resolve("ask");
    }
    this._pending.clear();
  }

  // --- State access (for output providers) ---------------------------------

  state(): BuddyState {
    return this._state;
  }

  subscribe(cb: StateListener): () => void {
    this._listeners.add(cb);
    return () => {
      this._listeners.delete(cb);
    };
  }

  // --- Input provider API --------------------------------------------------

  submitRequest(request: {
    requestId: string;
    agentId: string;
    tool: string;
    hint: string;
    source: string;
  }): void {
    this._apply({
      type: "request_arrived",
      at: Date.now(),
      requestId: request.requestId,
      agentId: request.agentId,
      tool: request.tool,
      hint: request.hint,
      source: request.source,
    });
  }

  registerPending(requestId: string, resolve: PendingResolve): void {
    this._pending.set(requestId, resolve);
  }

  expireRequest(requestId: string): void {
    const resolve = this._pending.get(requestId);
    if (resolve) {
      this._pending.delete(requestId);
      resolve("ask");
    }
    this._apply({
      type: "request_expired",
      at: Date.now(),
      requestId,
    });
  }

  clearRequest(requestId: string): void {
    // Clear might be called after decision already resolved the pending,
    // so it's fine if the pending entry doesn't exist.
    const resolve = this._pending.get(requestId);
    if (resolve) {
      this._pending.delete(requestId);
    }
    this._apply({
      type: "request_cleared",
      at: Date.now(),
      requestId,
    });
  }

  agentConnected(agentId: string): void {
    this._apply({
      type: "agent_connected",
      at: Date.now(),
      agentId,
    });
  }

  agentDisconnected(agentId: string): void {
    this._apply({
      type: "agent_disconnected",
      at: Date.now(),
      agentId,
    });
  }

  activitySignal(agentId: string, signal: ActivitySignalKind): void {
    this._apply({
      type: "activity_signal",
      at: Date.now(),
      agentId,
      signal,
    });
  }

  // --- Output provider API (decisions from users) --------------------------

  handleDecide(
    clientId: string,
    requestId: string,
    decision: string,
  ): [ok: boolean, error: ErrorCode | null] {
    if (decision !== "approve" && decision !== "deny") {
      return [false, "E_BAD_MESSAGE"];
    }

    const now = Date.now();

    // Rate limit per client.
    const last = this._clientLastDecide.get(clientId) ?? 0;
    if (now - last < this._config.decideMinIntervalMs) {
      return [false, "E_RATE_LIMIT"];
    }

    const cur = this._state;
    if (!cur.prompt) return [false, "E_NO_ACTIVE_PROMPT"];
    if (cur.prompt.id !== requestId) return [false, "E_PROMPT_ID_MISMATCH"];
    if (cur.prompt.decidedBy !== null) return [false, "E_ALREADY_DECIDED"];
    if (cur.desktop.status === "disconnected") return [false, "E_DESKTOP_DISCONNECTED"];

    this._clientLastDecide.set(clientId, now);

    // Apply the decision to state.
    this._apply({
      type: "request_decided",
      at: now,
      requestId,
      clientId,
      decision: decision as "approve" | "deny",
    });

    // Resolve the pending promise so the input provider can respond.
    const resolve = this._pending.get(requestId);
    if (resolve) {
      this._pending.delete(requestId);
      resolve(decision);
    }

    return [true, null];
  }

  // --- Internal ------------------------------------------------------------

  private _apply(event: Event): void {
    const prev = this._state;
    const next = reduce(prev, event);
    if (next === prev) return;
    this._state = next;
    for (const cb of this._listeners) {
      try {
        cb(prev, next);
      } catch {
        // Listener errors must not crash the engine.
      }
    }
  }

  private _pruneClientRateLimit(): void {
    const cutoff = Date.now() - 60_000;
    for (const [id, ts] of this._clientLastDecide) {
      if (ts < cutoff) this._clientLastDecide.delete(id);
    }
  }
}
