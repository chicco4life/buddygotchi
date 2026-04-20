/**
 * Web output: WebSocket server + pairing.
 *
 * Handles WS connections at /ws, authenticates via pairing codes/tokens,
 * broadcasts state snapshots and patches, and receives user decisions.
 */

import { randomBytes, randomUUID } from "crypto";
import { readFileSync, writeFileSync, mkdirSync, existsSync } from "fs";
import { join } from "path";
import type { ServerWebSocket } from "bun";
import type { Engine, StateListener } from "../core/engine.js";
import type { OutputProvider } from "./base.js";
import type { BuddyState } from "../../schema/state.js";
import type { ErrorCode } from "../../schema/errors.js";

const PROTOCOL_VERSION = 1;
const VERSION = "0.2.0";
const SESSION_ID = randomUUID().slice(0, 12);

// Ambiguous chars removed for readability.
const CODE_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

// ---------------------------------------------------------------------------
// Pairing Manager
// ---------------------------------------------------------------------------

export class PairingManager {
  private _code: string | null = null;
  private _codeCreatedAt = 0;
  private _ttlS: number;
  private _tokens: Map<string, string>; // clientId -> token
  private _statePath: string;

  constructor(statePath: string, ttlS: number) {
    this._ttlS = ttlS;
    this._statePath = statePath;
    this._tokens = this._loadTokens();
  }

  rotateCode(): string {
    this._code = Array.from({ length: 6 }, () =>
      CODE_CHARS[Math.floor(Math.random() * CODE_CHARS.length)],
    ).join("");
    this._codeCreatedAt = Date.now();
    return this._code;
  }

  currentCode(): string | null {
    if (!this._code) return null;
    if (Date.now() - this._codeCreatedAt > this._ttlS * 1000) return null;
    return this._code;
  }

  authorize(
    clientId: string,
    pairingCode?: string,
    token?: string,
  ): { ok: boolean; error?: ErrorCode; issuedToken?: string } {
    // Token-based re-auth.
    if (token) {
      const stored = this._tokens.get(clientId);
      if (stored && stored === token) return { ok: true };
      return { ok: false, error: "E_PAIRING_INVALID" };
    }

    // Code-based first-time auth.
    if (pairingCode) {
      const current = this.currentCode();
      if (!current || pairingCode.toUpperCase() !== current) {
        return { ok: false, error: "E_PAIRING_INVALID" };
      }
      // Consume the code.
      this._code = null;
      // Issue a token.
      const newToken = randomBytes(32).toString("base64url");
      this._tokens.set(clientId, newToken);
      this._saveTokens();
      return { ok: true, issuedToken: newToken };
    }

    return { ok: false, error: "E_PAIRING_REQUIRED" };
  }

  private _loadTokens(): Map<string, string> {
    try {
      const data = readFileSync(this._statePath, "utf-8");
      const obj = JSON.parse(data);
      if (obj && typeof obj.tokens === "object") {
        return new Map(Object.entries(obj.tokens));
      }
    } catch {
      // No file or invalid — start fresh.
    }
    return new Map();
  }

  private _saveTokens(): void {
    const dir = this._statePath.replace(/\/[^/]+$/, "");
    if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
    const data = JSON.stringify({
      tokens: Object.fromEntries(this._tokens),
    });
    writeFileSync(this._statePath, data, "utf-8");
  }
}

// ---------------------------------------------------------------------------
// WebSocket connection state
// ---------------------------------------------------------------------------

export interface WsData {
  clientId: string | null;
  authed: boolean;
  lastVersion: number;
}

// ---------------------------------------------------------------------------
// Web Output Provider
// ---------------------------------------------------------------------------

export class WebOutput implements OutputProvider {
  readonly outputId = "web";
  private _engine: Engine | null = null;
  private _pairing: PairingManager;
  private _unsub: (() => void) | null = null;
  private _connections = new Set<ServerWebSocket<WsData>>();

  constructor(pairing: PairingManager) {
    this._pairing = pairing;
  }

  get pairing(): PairingManager {
    return this._pairing;
  }

  async start(engine: Engine): Promise<void> {
    this._engine = engine;
    this._unsub = engine.subscribe(this._onStateChange.bind(this));
  }

  async stop(): Promise<void> {
    if (this._unsub) {
      this._unsub();
      this._unsub = null;
    }
    for (const ws of this._connections) {
      ws.close(1001, "shutting down");
    }
    this._connections.clear();
  }

  /** Called by Bun's WebSocket handler when a connection opens. */
  onOpen(ws: ServerWebSocket<WsData>): void {
    this._connections.add(ws);
  }

  /** Called by Bun's WebSocket handler when a connection closes. */
  onClose(ws: ServerWebSocket<WsData>): void {
    this._connections.delete(ws);
  }

  /** Called by Bun's WebSocket handler when a text message arrives. */
  onMessage(ws: ServerWebSocket<WsData>, raw: string): void {
    let msg: Record<string, unknown>;
    try {
      msg = JSON.parse(raw);
    } catch {
      this._sendError(ws, null, "E_BAD_MESSAGE", "invalid_json");
      return;
    }
    if (typeof msg !== "object" || msg === null) {
      this._sendError(ws, null, "E_BAD_MESSAGE", "not_object");
      return;
    }

    const mtype = msg.type;

    if (mtype === "hello") {
      this._handleHello(ws, msg);
      return;
    }

    if (!ws.data.authed) {
      this._sendError(ws, msg.reqId as string | null, "E_PAIRING_REQUIRED");
      return;
    }

    if (mtype === "decide") {
      this._handleDecide(ws, msg);
      return;
    }
    if (mtype === "ping") {
      ws.send(JSON.stringify({ type: "ack", reqId: msg.reqId ?? "", ok: true }));
      return;
    }
    if (mtype === "subscribe") {
      ws.send(JSON.stringify({ type: "ack", reqId: msg.reqId ?? "", ok: true }));
      return;
    }

    this._sendError(ws, msg.reqId as string | null, "E_UNSUPPORTED", `type=${mtype}`);
  }

  // --- Message handlers ----------------------------------------------------

  private _handleHello(ws: ServerWebSocket<WsData>, msg: Record<string, unknown>): void {
    if (msg.protocolVersion !== PROTOCOL_VERSION) {
      this._sendError(ws, null, "E_UNSUPPORTED", `protocol=${msg.protocolVersion}`);
      ws.close();
      return;
    }

    const clientId = msg.clientId;
    if (typeof clientId !== "string" || !clientId) {
      this._sendError(ws, null, "E_BAD_MESSAGE", "missing_clientId");
      return;
    }
    ws.data.clientId = clientId;

    const outcome = this._pairing.authorize(
      clientId,
      msg.pairingCode as string | undefined,
      msg.token as string | undefined,
    );

    if (!outcome.ok) {
      this._sendError(ws, null, outcome.error ?? "E_PAIRING_INVALID");
      return;
    }

    ws.data.authed = true;
    const state = this._engine!.state();
    ws.data.lastVersion = state.version;

    const welcome: Record<string, unknown> = {
      type: "welcome",
      protocolVersion: PROTOCOL_VERSION,
      serverVersion: VERSION,
      sessionId: SESSION_ID,
      state,
    };
    if (outcome.issuedToken) {
      welcome.issuedToken = outcome.issuedToken;
    }
    ws.send(JSON.stringify(welcome));
  }

  private _handleDecide(ws: ServerWebSocket<WsData>, msg: Record<string, unknown>): void {
    const reqId = msg.reqId as string;
    const promptId = msg.promptId as string;
    const decision = msg.decision as string;

    if (!reqId || !promptId || !decision) {
      this._sendError(ws, reqId ?? null, "E_BAD_MESSAGE");
      return;
    }

    // Map WS wire "once" → engine "approve"
    const engineDecision = decision === "once" ? "approve" : decision;

    const [ok, err] = this._engine!.handleDecide(
      ws.data.clientId!,
      promptId,
      engineDecision,
    );

    if (ok) {
      ws.send(JSON.stringify({ type: "ack", reqId, ok: true }));
    } else {
      this._sendError(ws, reqId, err ?? "E_BAD_MESSAGE");
    }
  }

  // --- State broadcasting --------------------------------------------------

  private _onStateChange(prev: BuddyState, next: BuddyState): void {
    for (const ws of this._connections) {
      if (!ws.data.authed) continue;

      if (
        next.version - ws.data.lastVersion > 1 ||
        prev.version !== ws.data.lastVersion
      ) {
        ws.send(JSON.stringify({ type: "snapshot", state: next }));
      } else {
        const changes = shallowDiff(prev, next);
        ws.send(
          JSON.stringify({
            type: "patch",
            version: next.version,
            prevVersion: prev.version,
            changes,
          }),
        );
      }
      ws.data.lastVersion = next.version;
    }
  }

  // --- Helpers -------------------------------------------------------------

  private _sendError(
    ws: ServerWebSocket<WsData>,
    reqId: string | null,
    code: ErrorCode,
    detail?: string,
  ): void {
    const payload: Record<string, unknown> = {
      type: "ack",
      reqId: reqId ?? "",
      ok: false,
      error: code,
    };
    if (detail) payload.detail = detail;
    ws.send(JSON.stringify(payload));
  }
}

// ---------------------------------------------------------------------------
// Utility
// ---------------------------------------------------------------------------

const DIFF_FIELDS = [
  "version", "updatedAt", "msg", "tokens", "tokensToday", "owner",
  "desktop", "sessions", "pet", "entries", "prompt",
] as const;

function shallowDiff(
  prev: BuddyState,
  next: BuddyState,
): Partial<BuddyState> {
  const out: Record<string, unknown> = {};
  for (const f of DIFF_FIELDS) {
    if (prev[f] !== next[f]) out[f] = next[f];
  }
  return out as Partial<BuddyState>;
}

export { SESSION_ID, VERSION };
