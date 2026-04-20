import { describe, expect, test } from "bun:test";
import { reduce, INITIAL_STATE, type InternalState } from "../../src/core/state";
import type { Event } from "../../src/core/events";

const NOW = 1_000_000;

function apply(state: InternalState, ...events: Event[]): InternalState {
  let s = state;
  for (const e of events) s = reduce(s, e);
  return s;
}

describe("reduce", () => {
  test("initial state is disconnected with no prompt", () => {
    const s = INITIAL_STATE;
    expect(s.version).toBe(0);
    expect(s.desktop.status).toBe("disconnected");
    expect(s.prompt).toBeNull();
    expect(s.pet.state).toBe("sleep");
  });

  test("agent_connected bumps version once", () => {
    const s = apply(INITIAL_STATE, {
      type: "agent_connected",
      at: NOW,
      agentId: "cursor",
    });
    expect(s.version).toBe(1);
    expect(s.desktop.status).toBe("connected");
    expect(s.pet.state).toBe("idle");
  });

  test("duplicate connect is a no-op", () => {
    const s1 = apply(INITIAL_STATE, {
      type: "agent_connected",
      at: NOW,
      agentId: "cursor",
    });
    const s2 = reduce(s1, {
      type: "agent_connected",
      at: NOW + 100,
      agentId: "cursor",
    });
    expect(s2).toBe(s1); // same object reference
  });

  test("request_arrived sets prompt and pet=attention", () => {
    let s = apply(INITIAL_STATE, {
      type: "agent_connected",
      at: NOW,
      agentId: "cursor",
    });
    s = apply(s, {
      type: "request_arrived",
      at: NOW + 1,
      requestId: "req_1",
      agentId: "cursor",
      tool: "Bash",
      hint: "ls -la",
      source: "cursor",
    });
    expect(s.prompt).not.toBeNull();
    expect(s.prompt!.id).toBe("req_1");
    expect(s.prompt!.tool).toBe("Bash");
    expect(s.prompt!.decidedBy).toBeNull();
    expect(s.pet.state).toBe("attention");
  });

  test("request_decided sets decidedBy", () => {
    let s = apply(
      INITIAL_STATE,
      { type: "agent_connected", at: NOW, agentId: "cursor" },
      {
        type: "request_arrived",
        at: NOW + 1,
        requestId: "req_1",
        agentId: "cursor",
        tool: "Bash",
        hint: "ls",
        source: "cursor",
      },
    );
    s = apply(s, {
      type: "request_decided",
      at: NOW + 2,
      requestId: "req_1",
      clientId: "web-abc",
      decision: "approve",
    });
    expect(s.prompt!.decidedBy).not.toBeNull();
    expect(s.prompt!.decidedBy!.clientId).toBe("web-abc");
    // "approve" maps to "once" on the wire
    expect(s.prompt!.decidedBy!.decision).toBe("once");
  });

  test("second decide for same request is a no-op (first wins)", () => {
    let s = apply(
      INITIAL_STATE,
      { type: "agent_connected", at: NOW, agentId: "cursor" },
      {
        type: "request_arrived",
        at: NOW + 1,
        requestId: "req_1",
        agentId: "cursor",
        tool: "Bash",
        hint: "ls",
        source: "cursor",
      },
      {
        type: "request_decided",
        at: NOW + 2,
        requestId: "req_1",
        clientId: "web-abc",
        decision: "approve",
      },
    );
    const prev = s;
    s = reduce(s, {
      type: "request_decided",
      at: NOW + 3,
      requestId: "req_1",
      clientId: "web-def",
      decision: "deny",
    });
    expect(s).toBe(prev); // same object — no-op
  });

  test("request_cleared removes prompt", () => {
    let s = apply(
      INITIAL_STATE,
      { type: "agent_connected", at: NOW, agentId: "cursor" },
      {
        type: "request_arrived",
        at: NOW + 1,
        requestId: "req_1",
        agentId: "cursor",
        tool: "Bash",
        hint: "ls",
        source: "cursor",
      },
    );
    s = apply(s, {
      type: "request_cleared",
      at: NOW + 2,
      requestId: "req_1",
    });
    expect(s.prompt).toBeNull();
    expect(s.pet.state).toBe("idle");
  });

  test("request_expired removes prompt", () => {
    let s = apply(
      INITIAL_STATE,
      { type: "agent_connected", at: NOW, agentId: "cursor" },
      {
        type: "request_arrived",
        at: NOW + 1,
        requestId: "req_1",
        agentId: "cursor",
        tool: "Bash",
        hint: "ls",
        source: "cursor",
      },
    );
    s = apply(s, {
      type: "request_expired",
      at: NOW + 2,
      requestId: "req_1",
    });
    expect(s.prompt).toBeNull();
  });

  test("agent_disconnected flips desktop and pet=sleep", () => {
    let s = apply(INITIAL_STATE, {
      type: "agent_connected",
      at: NOW,
      agentId: "cursor",
    });
    s = apply(s, {
      type: "agent_disconnected",
      at: NOW + 1,
      agentId: "cursor",
    });
    expect(s.desktop.status).toBe("disconnected");
    expect(s.pet.state).toBe("sleep");
  });

  test("stale_tick fires after threshold", () => {
    let s = apply(INITIAL_STATE, {
      type: "agent_connected",
      at: NOW,
      agentId: "cursor",
    });
    // Touch agent so lastSeenAt is set via a request
    s = apply(s, {
      type: "request_arrived",
      at: NOW,
      requestId: "req_1",
      agentId: "cursor",
      tool: "Bash",
      hint: "ls",
      source: "cursor",
    });
    s = apply(s, {
      type: "request_cleared",
      at: NOW + 1,
      requestId: "req_1",
    });

    // Before threshold — no change
    const before = reduce(s, { type: "stale_tick", at: NOW + 20_000 });
    expect(before.desktop.status).toBe("connected");

    // After threshold — goes stale
    const after = reduce(s, { type: "stale_tick", at: NOW + 40_000 });
    expect(after.desktop.status).toBe("stale");
    expect(after.pet.state).toBe("sleep");
  });

  test("decide for wrong request_id is a no-op", () => {
    let s = apply(
      INITIAL_STATE,
      { type: "agent_connected", at: NOW, agentId: "cursor" },
      {
        type: "request_arrived",
        at: NOW + 1,
        requestId: "req_1",
        agentId: "cursor",
        tool: "Bash",
        hint: "ls",
        source: "cursor",
      },
    );
    const prev = s;
    s = reduce(s, {
      type: "request_decided",
      at: NOW + 2,
      requestId: "req_WRONG",
      clientId: "web-abc",
      decision: "approve",
    });
    expect(s).toBe(prev);
  });

  test("decide without prompt is a no-op", () => {
    const s = apply(INITIAL_STATE, {
      type: "agent_connected",
      at: NOW,
      agentId: "cursor",
    });
    const next = reduce(s, {
      type: "request_decided",
      at: NOW + 1,
      requestId: "req_1",
      clientId: "web-abc",
      decision: "approve",
    });
    expect(next).toBe(s);
  });

  test("version bumps exactly once per change", () => {
    let s = INITIAL_STATE;
    s = apply(s, { type: "agent_connected", at: NOW, agentId: "cursor" });
    expect(s.version).toBe(1);
    s = apply(s, {
      type: "request_arrived",
      at: NOW + 1,
      requestId: "r1",
      agentId: "cursor",
      tool: "T",
      hint: "h",
      source: "cursor",
    });
    expect(s.version).toBe(2);
  });

  test("multiple agents tracked independently", () => {
    let s = apply(
      INITIAL_STATE,
      { type: "agent_connected", at: NOW, agentId: "cursor" },
      { type: "agent_connected", at: NOW + 1, agentId: "claude-code" },
    );
    expect(s.agents.length).toBe(2);
    expect(s.desktop.status).toBe("connected");

    // Disconnect one — still connected via other
    s = apply(s, { type: "agent_disconnected", at: NOW + 2, agentId: "cursor" });
    expect(s.desktop.status).toBe("connected");

    // Disconnect both — now disconnected
    s = apply(s, {
      type: "agent_disconnected",
      at: NOW + 3,
      agentId: "claude-code",
    });
    expect(s.desktop.status).toBe("disconnected");
  });
});
