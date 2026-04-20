// Boundary [B]: daemon <-> web client over WebSocket.
//
// Transport: ws://<host>:8080/ws, one JSON object per frame, UTF-8.
// State-oriented (not pass-through). The web client never learns the
// BLE wire format.

import type { BuddyState } from "./state";
import type { ErrorCode } from "./errors";

export const PROTOCOL_VERSION = 1 as const;
export type ProtocolVersion = typeof PROTOCOL_VERSION;

// ---------------------------------------------------------------------------
// Client -> Server
// ---------------------------------------------------------------------------

// First frame after WS open. Required; no other message is accepted
// until hello succeeds.
export interface Hello {
  type: "hello";
  protocolVersion: ProtocolVersion;
  clientId: string;           // stable uuid, persisted in client storage
  pairingCode?: string;       // required on first contact for this clientId
  token?: string;             // bearer, issued after successful pairing
  lastVersion?: number;       // state.version client last saw, triggers resync
}

export interface Decide {
  type: "decide";
  reqId: string;              // client-generated, used for ack matching
  promptId: string;           // must equal current state.prompt.id
  decision: "once" | "deny";
}

export interface Subscribe {
  type: "subscribe";
  channels: Array<"state" | "log">;
}

export interface Ping {
  type: "ping";
  reqId: string;
}

export type ClientMsg = Hello | Decide | Subscribe | Ping;

// ---------------------------------------------------------------------------
// Server -> Client
// ---------------------------------------------------------------------------

// Reply to a successful hello. Always carries a full snapshot.
export interface Welcome {
  type: "welcome";
  protocolVersion: ProtocolVersion;
  serverVersion: string;      // daemon semver
  sessionId: string;          // new per daemon start; clients invalidate cache on change
  issuedToken?: string;       // present iff hello authenticated via pairingCode
  state: BuddyState;
}

export interface Snapshot {
  type: "snapshot";
  state: BuddyState;
}

// Shallow merge over current state. prevVersion MUST equal the client's
// last seen state.version; otherwise client forces a fresh hello.
// Nested objects (desktop, sessions, prompt, pet) are REPLACED atomically,
// not deep-merged.
export interface Patch {
  type: "patch";
  version: number;            // new state.version after applying changes
  prevVersion: number;        // state.version before applying
  changes: Partial<BuddyState>;
}

export interface Ack {
  type: "ack";
  reqId: string;              // echoes client's reqId
  ok: boolean;
  error?: ErrorCode;
  detail?: string;            // human-readable, never machine-parsed
}

export interface LogLine {
  type: "log";
  level: "info" | "warn" | "error";
  line: string;
}

export type ServerMsg = Welcome | Snapshot | Patch | Ack | LogLine;
