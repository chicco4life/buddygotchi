import { describe, expect, test, beforeEach } from "bun:test";
import { Engine } from "../../src/core/engine";
import { loadConfig } from "../../src/core/config";
import { ClaudeCodeInput } from "../../src/inputs/claude-code";

describe("ClaudeCodeInput", () => {
  let engine: Engine;
  let input: ClaudeCodeInput;

  beforeEach(async () => {
    engine = new Engine({ ...loadConfig(), decideMinIntervalMs: 0 });
    engine.start();
    input = new ClaudeCodeInput();
    await input.start(engine);
  });

  test("handleRequest submits prompt and returns allow on approve", async () => {
    const promise = input.handleRequest({
      tool: "Bash",
      hint: "npm install",
      source: "claude-code",
      timeout_s: 1,
    });

    await new Promise((r) => setTimeout(r, 10));

    const state = engine.state();
    expect(state.prompt).not.toBeNull();

    const promptId = state.prompt!.id;
    engine.handleDecide("test-client", promptId, "approve");

    const response = await promise;
    const body = await response.json();
    // Claude Code adapter also returns {decision: "allow"} (same as cursor)
    expect(body.decision).toBe("allow");
  });

  test("handleRequest returns ask on timeout", async () => {
    const response = await input.handleRequest({
      tool: "Bash",
      hint: "ls",
      source: "claude-code",
      timeout_s: 0.1,
    });
    const body = await response.json();
    expect(body.decision).toBe("ask");
  });

  test("request id is prefixed with cc_", async () => {
    const promise = input.handleRequest({
      tool: "Bash",
      hint: "ls",
      source: "claude-code",
      timeout_s: 1,
    });

    await new Promise((r) => setTimeout(r, 10));

    const state = engine.state();
    expect(state.prompt!.id).toStartWith("cc_");

    // Clean up
    engine.expireRequest(state.prompt!.id);
    await promise;
  });
});
