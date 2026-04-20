/**
 * `buddygotchi signal` — fire-and-forget activity signal.
 *
 * Reads hook JSON from stdin, maps the hook event name to an activity
 * signal, POSTs to the daemon, and exits immediately. Never blocks.
 *
 * Usage:
 *   buddygotchi signal
 */

export default async function signal(): Promise<void> {
  const url =
    process.env.BUDDY_HOOK_URL?.replace(/\/hook\/request$/, "/hook/signal") ??
    "http://127.0.0.1:8080/hook/signal";

  let raw = "";
  try {
    raw = await Bun.stdin.text();
  } catch {
    process.exit(0);
  }

  let hookInput: Record<string, unknown> = {};
  try {
    hookInput = raw ? JSON.parse(raw) : {};
  } catch {
    process.exit(0);
  }

  const hookEvent = (hookInput.hook_event_name as string) ?? "";
  const signalKind = mapHookToSignal(hookEvent);
  if (!signalKind) {
    process.exit(0);
  }

  try {
    await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ agent_id: "claude-code", signal: signalKind }),
      signal: AbortSignal.timeout(3000),
    });
  } catch {
    // Best effort — never block Claude.
  }
  process.exit(0);
}

function mapHookToSignal(hookEvent: string): string | null {
  switch (hookEvent) {
    case "UserPromptSubmit":
      return "start_working";
    case "PostToolUse":
    case "SubagentStart":
      return "keep_working";
    case "Stop":
    case "StopFailure":
      return "stop_working";
    case "TaskCompleted":
      return "celebrate";
    default:
      return null;
  }
}
