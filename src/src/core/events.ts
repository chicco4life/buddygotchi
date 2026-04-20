/**
 * Generic events fed into the reducer.
 *
 * Events come from three sources:
 * - Input providers (agent adapters), when hooks arrive or agents connect/disconnect
 * - Output providers (web clients), when a user sends a decision
 * - The engine's own staleness ticker
 *
 * Events are plain objects with a discriminated `type` field.
 * The reducer is the only thing allowed to turn an event into a new BuddyState.
 */

// ---------------------------------------------------------------------------
// Agent lifecycle
// ---------------------------------------------------------------------------

export interface AgentConnected {
  type: "agent_connected";
  at: number;
  agentId: string;
}

export interface AgentDisconnected {
  type: "agent_disconnected";
  at: number;
  agentId: string;
}

// ---------------------------------------------------------------------------
// Request lifecycle
// ---------------------------------------------------------------------------

export interface RequestArrived {
  type: "request_arrived";
  at: number;
  requestId: string;
  agentId: string;
  tool: string;
  hint: string;
  source: string;
}

export interface RequestDecided {
  type: "request_decided";
  at: number;
  requestId: string;
  clientId: string;
  decision: "approve" | "deny";
}

export interface RequestExpired {
  type: "request_expired";
  at: number;
  requestId: string;
}

export interface RequestCleared {
  type: "request_cleared";
  at: number;
  requestId: string;
}

// ---------------------------------------------------------------------------
// Activity signals (non-blocking lifecycle hooks)
// ---------------------------------------------------------------------------

export const ACTIVITY_SIGNAL_KINDS = [
  "start_working",
  "keep_working",
  "stop_working",
  "celebrate",
] as const;

export type ActivitySignalKind = (typeof ACTIVITY_SIGNAL_KINDS)[number];

export function isActivitySignalKind(value: unknown): value is ActivitySignalKind {
  return typeof value === "string" &&
    (ACTIVITY_SIGNAL_KINDS as readonly string[]).includes(value);
}

export interface ActivitySignal {
  type: "activity_signal";
  at: number;
  agentId: string;
  signal: ActivitySignalKind;
}

// ---------------------------------------------------------------------------
// Misc
// ---------------------------------------------------------------------------

export interface StaleTick {
  type: "stale_tick";
  at: number;
}

// ---------------------------------------------------------------------------
// Union
// ---------------------------------------------------------------------------

export type Event =
  | AgentConnected
  | AgentDisconnected
  | RequestArrived
  | RequestDecided
  | RequestExpired
  | RequestCleared
  | StaleTick
  | ActivitySignal;
