import { describe, expect, test, beforeEach } from "bun:test";
import { Engine } from "../../src/core/engine";
import { loadConfig, type Config } from "../../src/core/config";
import type { BuddyState } from "../../schema/state";

function makeConfig(overrides: Partial<Config> = {}): Config {
  return { ...loadConfig(), decideMinIntervalMs: 0, ...overrides };
}

describe("Engine", () => {
  let engine: Engine;

  beforeEach(() => {
    engine = new Engine(makeConfig());
  });

  test("submitRequest sets prompt in state", () => {
    engine.agentConnected("cursor");
    engine.submitRequest({
      requestId: "r1",
      agentId: "cursor",
      tool: "Bash",
      hint: "ls",
      source: "cursor",
    });
    const s = engine.state();
    expect(s.prompt).not.toBeNull();
    expect(s.prompt!.id).toBe("r1");
    expect(s.pet.state).toBe("attention");
  });

  test("handleDecide resolves pending promise", async () => {
    engine.agentConnected("cursor");

    let resolved: string | null = null;
    const promise = new Promise<string>((resolve) => {
      engine.registerPending("r1", resolve);
    }).then((d) => {
      resolved = d;
      return d;
    });

    engine.submitRequest({
      requestId: "r1",
      agentId: "cursor",
      tool: "Bash",
      hint: "ls",
      source: "cursor",
    });

    const [ok, err] = engine.handleDecide("web-abc", "r1", "approve");
    expect(ok).toBe(true);
    expect(err).toBeNull();

    await promise;
    expect(resolved).toBe("approve");
    expect(engine.state().prompt!.decidedBy).not.toBeNull();
  });

  test("handleDecide rejects with E_NO_ACTIVE_PROMPT when no prompt", () => {
    engine.agentConnected("cursor");
    const [ok, err] = engine.handleDecide("web-abc", "r1", "approve");
    expect(ok).toBe(false);
    expect(err).toBe("E_NO_ACTIVE_PROMPT");
  });

  test("handleDecide rejects with E_PROMPT_ID_MISMATCH for wrong id", () => {
    engine.agentConnected("cursor");
    engine.submitRequest({
      requestId: "r1",
      agentId: "cursor",
      tool: "Bash",
      hint: "ls",
      source: "cursor",
    });
    const [ok, err] = engine.handleDecide("web-abc", "r_WRONG", "approve");
    expect(ok).toBe(false);
    expect(err).toBe("E_PROMPT_ID_MISMATCH");
  });

  test("handleDecide rejects second decision with E_ALREADY_DECIDED", () => {
    engine.agentConnected("cursor");
    engine.registerPending("r1", () => {});
    engine.submitRequest({
      requestId: "r1",
      agentId: "cursor",
      tool: "Bash",
      hint: "ls",
      source: "cursor",
    });

    engine.handleDecide("web-abc", "r1", "approve");
    const [ok, err] = engine.handleDecide("web-def", "r1", "deny");
    expect(ok).toBe(false);
    expect(err).toBe("E_ALREADY_DECIDED");
  });

  test("handleDecide rejects when desktop disconnected", () => {
    // No agent connected → desktop is disconnected
    // Manually set a prompt by connecting then disconnecting
    engine.agentConnected("cursor");
    engine.submitRequest({
      requestId: "r1",
      agentId: "cursor",
      tool: "Bash",
      hint: "ls",
      source: "cursor",
    });
    engine.agentDisconnected("cursor");

    const [ok, err] = engine.handleDecide("web-abc", "r1", "approve");
    expect(ok).toBe(false);
    expect(err).toBe("E_DESKTOP_DISCONNECTED");
  });

  test("rate limiting rejects fast decisions", () => {
    const eng = new Engine(makeConfig({ decideMinIntervalMs: 10_000 }));
    eng.agentConnected("cursor");

    eng.registerPending("r1", () => {});
    eng.submitRequest({
      requestId: "r1",
      agentId: "cursor",
      tool: "Bash",
      hint: "ls",
      source: "cursor",
    });
    eng.handleDecide("web-abc", "r1", "approve");

    // Submit a new request
    eng.registerPending("r2", () => {});
    eng.submitRequest({
      requestId: "r2",
      agentId: "cursor",
      tool: "Bash",
      hint: "ls2",
      source: "cursor",
    });

    // Same client too fast
    const [ok, err] = eng.handleDecide("web-abc", "r2", "approve");
    expect(ok).toBe(false);
    expect(err).toBe("E_RATE_LIMIT");
  });

  test("subscribe receives state changes", () => {
    const changes: [BuddyState, BuddyState][] = [];
    engine.subscribe((prev, next) => changes.push([prev, next]));

    engine.agentConnected("cursor");
    expect(changes.length).toBe(1);
    expect(changes[0][0].desktop.status).toBe("disconnected");
    expect(changes[0][1].desktop.status).toBe("connected");
  });

  test("clearRequest removes prompt", () => {
    engine.agentConnected("cursor");
    engine.submitRequest({
      requestId: "r1",
      agentId: "cursor",
      tool: "Bash",
      hint: "ls",
      source: "cursor",
    });
    expect(engine.state().prompt).not.toBeNull();

    engine.clearRequest("r1");
    expect(engine.state().prompt).toBeNull();
  });

  test("expireRequest removes prompt", () => {
    engine.agentConnected("cursor");
    engine.submitRequest({
      requestId: "r1",
      agentId: "cursor",
      tool: "Bash",
      hint: "ls",
      source: "cursor",
    });
    engine.expireRequest("r1");
    expect(engine.state().prompt).toBeNull();
  });

  test("stop resolves pending requests with ask", async () => {
    engine.agentConnected("cursor");

    let resolved: string | null = null;
    const promise = new Promise<string>((resolve) => {
      engine.registerPending("r1", resolve);
    }).then((d) => {
      resolved = d;
      return d;
    });

    engine.submitRequest({
      requestId: "r1",
      agentId: "cursor",
      tool: "Bash",
      hint: "ls",
      source: "cursor",
    });

    engine.stop();
    await promise;
    expect(resolved).toBe("ask");
  });
});
