/**
 * `buddygotchi daemon` — starts the HTTP/WS server.
 *
 * Wires all three layers: creates Engine, input providers, output providers,
 * and the Bun HTTP server. Serves static web UI from src/web/.
 */

import { join, resolve, dirname } from "path";
import { existsSync, mkdirSync } from "fs";
import { loadConfig } from "../core/config.js";
import { Engine } from "../core/engine.js";
import { isActivitySignalKind } from "../core/events.js";
import { CursorInput } from "../inputs/cursor.js";
import { ClaudeCodeInput } from "../inputs/claude-code.js";
import { CodexInput } from "../inputs/codex.js";
import { WebOutput, PairingManager, SESSION_ID, VERSION, type WsData } from "../outputs/web.js";
import type { ServerWebSocket } from "bun";

export default async function daemon(): Promise<void> {
  const config = loadConfig();

  // State directory for persistent pairing tokens.
  if (!existsSync(config.stateDir)) {
    mkdirSync(config.stateDir, { recursive: true });
  }

  const engine = new Engine(config);
  const pairing = new PairingManager(
    join(config.stateDir, "pairing-state.json"),
    config.pairingCodeTtlS,
  );
  const code = pairing.rotateCode();

  // Input providers.
  const cursorInput = new CursorInput();
  const claudeCodeInput = new ClaudeCodeInput();
  const codexInput = new CodexInput();
  const inputs = [cursorInput, claudeCodeInput, codexInput];

  // Output providers.
  const webOutput = new WebOutput(pairing);

  // Locate web client files.
  const webRoot = locateWebRoot(config.webRoot);

  // Start the Bun HTTP + WS server.
  const server = Bun.serve<WsData>({
    hostname: config.httpHost,
    port: config.httpPort,

    async fetch(req, server) {
      const url = new URL(req.url);
      const path = url.pathname;

      // WebSocket upgrade.
      if (path === "/ws") {
        const upgraded = server.upgrade<WsData>(req, {
          data: { clientId: null, authed: false, lastVersion: -1 },
        });
        if (!upgraded) {
          return new Response("WebSocket upgrade failed", { status: 400 });
        }
        return undefined as unknown as Response;
      }

      // Health check.
      if (path === "/healthz" && req.method === "GET") {
        const state = engine.state();
        return Response.json({
          ok: true,
          serverVersion: VERSION,
          sessionId: SESSION_ID,
          stateVersion: state.version,
          desktop: state.desktop.status,
        });
      }

      // Pairing code (loopback only).
      if (path === "/pair/current" && req.method === "GET") {
        const currentCode = pairing.currentCode();
        const rotated = !currentCode;
        const finalCode = currentCode ?? pairing.rotateCode();
        return Response.json({
          code: finalCode,
          ttlSeconds: config.pairingCodeTtlS,
          rotated,
        });
      }

      // Hook endpoints — route to appropriate input adapter.
      if (req.method === "POST") {
        let body: Record<string, unknown>;
        try {
          body = await req.json() as Record<string, unknown>;
        } catch {
          return Response.json({ error: "invalid_json" }, { status: 400 });
        }

        if (path === "/hook/signal") {
          const agentId = typeof body.agent_id === "string" ? body.agent_id : "claude-code";
          const sig = typeof body.signal === "string" ? body.signal : "";
          if (!isActivitySignalKind(sig)) {
            return Response.json({ error: "invalid_signal" }, { status: 400 });
          }
          engine.activitySignal(agentId, sig);
          return Response.json({ ok: true });
        }

        if (path === "/hook/cursor") {
          return cursorInput.handleRequest(body);
        }
        if (path === "/hook/claude-code") {
          return claudeCodeInput.handleRequest(body);
        }
        if (path === "/hook/codex") {
          return codexInput.handleRequest(body);
        }

        // Legacy backward-compatible route: dispatch by source field.
        if (path === "/hook/request") {
          const source = typeof body.source === "string" ? body.source : "";
          if (source === "claude-code") {
            return claudeCodeInput.handleRequest(body);
          }
          // Default to cursor for backward compat.
          return cursorInput.handleRequest(body);
        }
      }

      // Static web UI.
      if (webRoot && req.method === "GET") {
        if (path === "/" || path === "/index.html") {
          const file = Bun.file(join(webRoot, "index.html"));
          if (await file.exists()) return new Response(file);
        }
        const filePath = join(webRoot, path.slice(1));
        const file = Bun.file(filePath);
        if (await file.exists()) return new Response(file);
        // SPA fallback.
        const index = Bun.file(join(webRoot, "index.html"));
        if (await index.exists()) return new Response(index);
      }

      return new Response("Not Found", { status: 404 });
    },

    websocket: {
      open(ws: ServerWebSocket<WsData>) {
        webOutput.onOpen(ws);
      },
      close(ws: ServerWebSocket<WsData>) {
        webOutput.onClose(ws);
      },
      message(ws: ServerWebSocket<WsData>, message) {
        if (typeof message === "string") {
          webOutput.onMessage(ws, message);
        }
      },
    },
  });

  // Start engine and providers.
  engine.start();
  for (const input of inputs) {
    await input.start(engine);
  }
  await webOutput.start(engine);

  // Banner.
  const host = config.httpHost === "0.0.0.0" ? "localhost" : config.httpHost;
  const port = server.port;
  const bar = "=".repeat(56);
  console.log(bar);
  console.log(`buddygotchi daemon  session=${SESSION_ID}`);
  console.log(`Web UI         http://${host}:${port}/`);
  console.log(`WebSocket      ws://${host}:${port}/ws`);
  console.log(`Hook (cursor)  http://${host}:${port}/hook/cursor      (POST)`);
  console.log(`Hook (claude)  http://${host}:${port}/hook/claude-code  (POST)`);
  console.log(`Hook (legacy)  http://${host}:${port}/hook/request      (POST)`);
  console.log(`Signal         http://${host}:${port}/hook/signal       (POST)`);
  console.log(`Health         http://${host}:${port}/healthz`);
  console.log();
  console.log(`Pairing code   ${code}   (valid ${config.pairingCodeTtlS}s)`);
  console.log(bar);

  // Graceful shutdown.
  process.on("SIGINT", () => shutdown());
  process.on("SIGTERM", () => shutdown());

  async function shutdown(): Promise<void> {
    console.log("\nshutting down");
    for (const input of inputs) {
      await input.stop();
    }
    await webOutput.stop();
    engine.stop();
    server.stop();
    process.exit(0);
  }
}

function locateWebRoot(override: string | null): string | null {
  if (override) {
    const p = resolve(override);
    if (existsSync(join(p, "index.html"))) return p;
  }

  // Relative to this file: src/cli/daemon.ts → src/web/ (symlink to outputs/web/client/)
  const candidate = resolve(dirname(new URL(import.meta.url).pathname), "../web");
  if (existsSync(join(candidate, "index.html"))) return candidate;

  // Direct path to outputs/web/client/
  const outputs = resolve(dirname(new URL(import.meta.url).pathname), "../../outputs/web/client");
  if (existsSync(join(outputs, "index.html"))) return outputs;

  return null;
}
