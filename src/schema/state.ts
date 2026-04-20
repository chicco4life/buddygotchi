// The one shape the web UI renders from, produced by the daemon's
// reducer. This is the single source of truth across daemon, WS
// protocol, and web client.
//
// Any change here must: (1) bump BuddyState.version semantics if
// breaking, (2) update the reducer in src/core/state.ts,
// (3) update ws-protocol.ts snapshot/patch shapes automatically since
// they reference this type.

export type PetState =
  | "sleep"
  | "idle"
  | "busy"
  | "attention"
  | "celebrate"
  | "dizzy"
  | "heart";

export type DesktopStatus = "disconnected" | "connected" | "stale";

export interface DesktopLink {
  status: DesktopStatus;
  lastHeartbeatAt: number | null; // daemon epoch ms
  secure: boolean; // BLE link encrypted; MVP: false
}

export interface SessionCounts {
  total: number;
  running: number;
  waiting: number;
}

export interface PendingDecision {
  clientId: string;
  decision: "once" | "deny";
  at: number; // daemon epoch ms
}

export interface Prompt {
  id: string;
  tool: string;
  hint: string;
  arrivedAt: number; // daemon epoch ms
  decidedBy: PendingDecision | null;
}

export interface Pet {
  state: PetState;
  oneShotUntil: number | null; // epoch ms, for celebrate/dizzy/heart
  species: "bufo"; // MVP fixed
}

export interface BuddyState {
  version: number; // monotonic per daemon session
  updatedAt: number; // daemon epoch ms

  desktop: DesktopLink;
  sessions: SessionCounts;

  msg: string;
  entries: string[]; // newest first, max 10
  tokens: number;
  tokensToday: number;

  prompt: Prompt | null;
  pet: Pet;
  owner: string;
  lastSignal: string | null;
}

export const INITIAL_BUDDY_STATE: BuddyState = {
  version: 0,
  updatedAt: 0,
  desktop: { status: "disconnected", lastHeartbeatAt: null, secure: false },
  sessions: { total: 0, running: 0, waiting: 0 },
  msg: "",
  entries: [],
  tokens: 0,
  tokensToday: 0,
  prompt: null,
  pet: { state: "sleep", oneShotUntil: null, species: "bufo" },
  owner: "",
  lastSignal: null,
};
