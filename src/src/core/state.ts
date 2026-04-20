/**
 * BuddyState + pure reducer.
 *
 * Imports types directly from schema/state.ts — the single source of truth.
 * The reducer is the only code that transitions state. Everything else reads.
 *
 * Contract (invariants):
 * 1. `version` is monotonic; reduce bumps by exactly 1 on change,
 *    returns the SAME state object otherwise.
 * 2. Reducer is pure: no logging, no time lookup, no I/O.
 *    `at` is always passed in via the event.
 * 3. Prompt replacement is atomic: an event either creates, decides,
 *    or clears the prompt. Decisions persist on prompt.decidedBy
 *    until a RequestCleared event removes them.
 */

import type {
  BuddyState,
  DesktopLink,
  DesktopStatus,
  Pet,
  PendingDecision,
  Prompt,
  SessionCounts,
} from "../../schema/state.js";
import { INITIAL_BUDDY_STATE } from "../../schema/state.js";
import type { Event } from "./events.js";
import type { ActivitySignalKind } from "./events.js";

export { INITIAL_BUDDY_STATE };
export type { BuddyState };

// Per-agent connection tracking (not in schema — internal to daemon).
export interface AgentLink {
  agentId: string;
  status: DesktopStatus;
  lastSeenAt: number | null;
}

// Extended state that includes agent-level tracking.
// The `desktop` field is derived from agents for wire compat.
export interface InternalState extends BuddyState {
  agents: AgentLink[];
  staleMs: number;
  lastActivitySignal: ActivitySignalKind | null;
}

export const INITIAL_STATE: InternalState = {
  ...INITIAL_BUDDY_STATE,
  agents: [],
  staleMs: 30_000,
  lastActivitySignal: null,
};

// ---------------------------------------------------------------------------
// Reducer
// ---------------------------------------------------------------------------

export function reduce(state: InternalState, event: Event): InternalState {
  const next = reduceInner(state, event);
  if (next === state) return state;
  return {
    ...next,
    version: state.version + 1,
    updatedAt: event.at,
  };
}

function reduceInner(state: InternalState, event: Event): InternalState {
  switch (event.type) {
    case "agent_connected":
      return handleAgentConnected(state, event.agentId, event.at);

    case "agent_disconnected":
      return handleAgentDisconnected(state, event.agentId);

    case "request_arrived":
      return handleRequestArrived(state, event);

    case "request_decided":
      return handleRequestDecided(state, event);

    case "request_expired":
    case "request_cleared":
      return handleRequestRemoved(state, event.requestId);

    case "stale_tick":
      return handleStaleTick(state, event.at);

    case "activity_signal":
      return handleActivitySignal(state, event);

    default:
      return state;
  }
}

// ---------------------------------------------------------------------------
// Event handlers
// ---------------------------------------------------------------------------

function handleAgentConnected(
  state: InternalState,
  agentId: string,
  at: number,
): InternalState {
  const existing = state.agents.find((a) => a.agentId === agentId);
  if (existing && existing.status === "connected") return state;

  const agents = existing
    ? state.agents.map((a) =>
        a.agentId === agentId
          ? { ...a, status: "connected" as const, lastSeenAt: at }
          : a,
      )
    : [...state.agents, { agentId, status: "connected" as const, lastSeenAt: at }];

  return applyAgents(state, agents, "agent_connected");
}

function handleAgentDisconnected(
  state: InternalState,
  agentId: string,
): InternalState {
  const existing = state.agents.find((a) => a.agentId === agentId);
  if (!existing || existing.status === "disconnected") return state;

  const agents = state.agents.map((a) =>
    a.agentId === agentId
      ? { ...a, status: "disconnected" as const }
      : a,
  );

  const allDisconnected = !agents.some((a) => a.status === "connected" || a.status === "stale");
  const next = applyAgents(state, agents, "agent_disconnected");
  if (allDisconnected) {
    return { ...next, lastActivitySignal: null };
  }
  return next;
}

function handleRequestArrived(
  state: InternalState,
  event: Extract<Event, { type: "request_arrived" }>,
): InternalState {
  // Update agent liveness.
  const agents = touchAgent(state.agents, event.agentId, event.at);

  const prompt: Prompt = {
    id: event.requestId,
    tool: event.tool,
    hint: event.hint,
    arrivedAt: event.at,
    decidedBy: null,
  };

  const desktop = deriveDesktop(agents);
  const active = agents.some((a) => a.status === "connected");
  const sessions: SessionCounts = { total: 1, running: 1, waiting: 1 };
  const pet = derivePet(prompt, sessions, active, state.lastActivitySignal, null);
  const msg = shortMsg(event.tool, event.hint, event.source);

  return {
    ...state,
    agents,
    desktop,
    sessions,
    prompt,
    pet,
    msg,
    entries: [msg, ...state.entries].slice(0, 10),
    lastSignal: `request_arrived:${event.tool}`,
  };
}

function handleRequestDecided(
  state: InternalState,
  event: Extract<Event, { type: "request_decided" }>,
): InternalState {
  if (!state.prompt || state.prompt.id !== event.requestId) return state;
  if (state.prompt.decidedBy !== null) return state; // first decision wins

  const wireDecision = event.decision === "approve" ? "once" : "deny";
  const decidedBy: PendingDecision = {
    clientId: event.clientId,
    decision: wireDecision as "once" | "deny",
    at: event.at,
  };

  return {
    ...state,
    prompt: { ...state.prompt, decidedBy },
    lastSignal: `request_decided:${event.decision}`,
  };
}

function handleRequestRemoved(
  state: InternalState,
  requestId: string,
): InternalState {
  if (!state.prompt || state.prompt.id !== requestId) return state;

  const sessions: SessionCounts = { total: 0, running: 0, waiting: 0 };
  const active = state.agents.some((a) => a.status === "connected");
  const pet = derivePet(null, sessions, active, state.lastActivitySignal, null);

  return {
    ...state,
    prompt: null,
    sessions,
    pet,
    lastSignal: "request_cleared",
  };
}

function handleStaleTick(state: InternalState, now: number): InternalState {
  let changed = false;
  const agents = state.agents
    .filter((a) => {
      if (a.status === "disconnected" && a.lastSeenAt !== null && now - a.lastSeenAt > state.staleMs) {
        changed = true;
        return false;
      }
      return true;
    })
    .map((a) => {
      if (
        a.status === "connected" &&
        a.lastSeenAt !== null &&
        now - a.lastSeenAt > state.staleMs
      ) {
        changed = true;
        return { ...a, status: "stale" as const };
      }
      return a;
    });

  // Check one-shot expiry.
  const oneShotExpired =
    state.pet.oneShotUntil !== null && now >= state.pet.oneShotUntil;
  if (oneShotExpired) changed = true;

  if (!changed) return state;

  const desktop = deriveDesktop(agents);
  const active = agents.some((a) => a.status === "connected");
  const pet = derivePet(
    state.prompt, state.sessions, active,
    state.lastActivitySignal,
    oneShotExpired ? null : state.pet.oneShotUntil,
  );
  return { ...state, agents, desktop, pet };
}

function handleActivitySignal(
  state: InternalState,
  event: Extract<Event, { type: "activity_signal" }>,
): InternalState {
  const agents = touchAgent(state.agents, event.agentId, event.at);
  const desktop = deriveDesktop(agents);
  const active = agents.some((a) => a.status === "connected");

  const oneShotUntil = event.signal === "celebrate" ? event.at + 2000 : null;

  const pet = derivePet(
    state.prompt, state.sessions, active,
    event.signal, oneShotUntil,
  );

  const msg = `[${event.agentId}] ${event.signal}`;

  return {
    ...state,
    agents,
    desktop,
    pet,
    lastActivitySignal: event.signal,
    lastSignal: event.signal,
    msg,
    entries: [msg, ...state.entries].slice(0, 10),
  };
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function applyAgents(state: InternalState, agents: AgentLink[], lastSignal?: string): InternalState {
  const desktop = deriveDesktop(agents);
  const active = agents.some((a) => a.status === "connected");
  const pet = derivePet(
    state.prompt, state.sessions, active,
    state.lastActivitySignal, state.pet.oneShotUntil,
  );
  const next: InternalState = { ...state, agents, desktop, pet };
  if (lastSignal !== undefined) next.lastSignal = lastSignal;
  return next;
}

function deriveDesktop(agents: AgentLink[]): DesktopLink {
  const connected = agents.filter((a) => a.status === "connected");
  const stale = agents.filter((a) => a.status === "stale");

  let status: DesktopStatus;
  if (connected.length > 0) {
    status = "connected";
  } else if (stale.length > 0) {
    status = "stale";
  } else {
    status = "disconnected";
  }

  // Latest heartbeat across all agents.
  const lastHeartbeatAt = agents.reduce<number | null>((best, a) => {
    if (a.lastSeenAt === null) return best;
    return best === null ? a.lastSeenAt : Math.max(best, a.lastSeenAt);
  }, null);

  return { status, lastHeartbeatAt, secure: false };
}

function derivePet(
  prompt: Prompt | null,
  sessions: SessionCounts,
  active: boolean,
  lastSignal: ActivitySignalKind | null,
  oneShotUntil: number | null,
): Pet {
  if (!active) return { state: "sleep", oneShotUntil: null, species: "bufo" };

  if (prompt !== null && prompt.decidedBy === null)
    return { state: "attention", oneShotUntil: null, species: "bufo" };

  if (oneShotUntil !== null)
    return { state: "celebrate", oneShotUntil, species: "bufo" };

  if (lastSignal === "start_working" || lastSignal === "keep_working")
    return { state: "busy", oneShotUntil: null, species: "bufo" };

  if (lastSignal === "stop_working")
    return { state: "idle", oneShotUntil: null, species: "bufo" };

  if (sessions.running >= 3)
    return { state: "busy", oneShotUntil: null, species: "bufo" };

  return { state: "idle", oneShotUntil: null, species: "bufo" };
}

function touchAgent(agents: AgentLink[], agentId: string, at: number): AgentLink[] {
  const existing = agents.find((a) => a.agentId === agentId);
  if (existing) {
    return agents.map((a) =>
      a.agentId === agentId
        ? { ...a, status: "connected" as const, lastSeenAt: at }
        : a,
    );
  }
  return [...agents, { agentId, status: "connected" as const, lastSeenAt: at }];
}

function shortMsg(tool: string, hint: string, source: string): string {
  const base = source && source !== "other" ? `[${source}] ${tool}` : tool;
  if (!hint) return base;
  const short = hint.length <= 60 ? hint : hint.slice(0, 57) + "...";
  return `${base}: ${short}`;
}

