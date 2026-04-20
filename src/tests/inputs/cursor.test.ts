import { describe, expect, test, beforeEach } from "bun:test";
import { Engine } from "../../src/core/engine";
import { loadConfig } from "../../src/core/config";
import { CursorInput } from "../../src/inputs/cursor";

describe("CursorInput", () => {
  let engine: Engine;
  let input: CursorInput;

  beforeEach(async () => {
    engine = new Engine({ ...loadConfig(), decideMinIntervalMs: 0 });
    engine.start();
    input = new CursorInput();
    await input.start(engine);
  });

  test("handleRequest submits prompt to engine", async () => {
    // Start the request in background (it blocks waiting for decision).
    const promise = input.handleRequest({
      tool: "Bash",
      hint: "ls -la",
      source: "cursor",
      timeout_s: 1,
    });

    // Wait a tick for the request to be submitted.
    await new Promise((r) => setTimeout(r, 10));

    // Engine should have a prompt now.
    const state = engine.state();
    expect(state.prompt).not.toBeNull();
    expect(state.prompt!.tool).toBe("Bash");
    expect(state.prompt!.hint).toBe("ls -la");
    expect(state.pet.state).toBe("attention");

    // Decide to approve.
    const promptId = state.prompt!.id;
    engine.handleDecide("test-client", promptId, "approve");

    // The request should resolve.
    const response = await promise;
    const body = await response.json();
    expect(body.decision).toBe("allow");
  });

  test("handleRequest returns ask on timeout", async () => {
    const response = await input.handleRequest({
      tool: "Bash",
      hint: "ls",
      source: "cursor",
      timeout_s: 0.1, // 100ms timeout
    });

    const body = await response.json();
    expect(body.decision).toBe("ask");
  });

  test("handleRequest returns deny correctly", async () => {
    const promise = input.handleRequest({
      tool: "Write",
      hint: "/etc/passwd",
      source: "cursor",
      timeout_s: 1,
    });

    await new Promise((r) => setTimeout(r, 10));

    const state = engine.state();
    const promptId = state.prompt!.id;
    engine.handleDecide("test-client", promptId, "deny");

    const response = await promise;
    const body = await response.json();
    expect(body.decision).toBe("deny");
  });

  test("handleRequest rejects missing tool", async () => {
    const response = await input.handleRequest({
      hint: "ls",
      source: "cursor",
      timeout_s: 1,
    });
    expect(response.status).toBe(400);
  });
});
