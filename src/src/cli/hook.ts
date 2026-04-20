/**
 * `buddygotchi hook` — thin PreToolUse hook.
 *
 * Reads hook JSON from stdin, POSTs to the daemon, writes the
 * agent-native response to stdout. Compiled into the same binary.
 *
 * Usage:
 *   buddygotchi hook --format cursor
 *   buddygotchi hook --format claude-code
 */

export default async function hook(): Promise<void> {
  const args = process.argv.slice(3);
  let format = "cursor";

  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--format" && args[i + 1]) {
      format = args[i + 1];
      i++;
    }
  }

  const url = process.env.BUDDY_HOOK_URL ?? "http://127.0.0.1:8080/hook/request";
  const timeout = parseFloat(process.env.BUDDY_HOOK_TIMEOUT ?? "55");

  // Read stdin.
  let raw = "";
  try {
    raw = await Bun.stdin.text();
  } catch {
    writeAndExit(fallbackResponse(format, "PreToolUse"));
    return;
  }

  let hookInput: Record<string, unknown> = {};
  try {
    hookInput = raw ? JSON.parse(raw) : {};
  } catch {
    hookInput = {};
  }

  const [tool, hint] = extractToolAndHint(hookInput);
  const hookEventName = typeof hookInput.hook_event_name === "string" ? hookInput.hook_event_name : "PreToolUse";
  const source = format === "claude-code" ? "claude-code" : "cursor";

  try {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), (timeout + 2) * 1000);

    const resp = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ tool, hint, source, timeout_s: timeout }),
      signal: controller.signal,
    });

    clearTimeout(timer);
    const body = (await resp.json()) as Record<string, unknown>;
    const decision = typeof body.decision === "string" ? body.decision : "ask";
    writeAndExit(formatResponse(format, decision, hookEventName));
  } catch {
    writeAndExit(fallbackResponse(format, hookEventName));
  }
}

function extractToolAndHint(
  input: Record<string, unknown>,
): [string, string] {
  const tool =
    (input.tool_name as string) ??
    (input.hook_event_name as string) ??
    "Shell";

  const candidates: string[] = [];
  for (const key of ["command", "user_prompt", "prompt"]) {
    const v = input[key];
    if (typeof v === "string" && v) candidates.push(v);
  }

  const ti = input.tool_input;
  if (ti && typeof ti === "object") {
    const toolInput = ti as Record<string, unknown>;
    for (const key of ["command", "file_path", "path", "url", "query"]) {
      const v = toolInput[key];
      if (typeof v === "string" && v) candidates.push(v);
    }
    if (candidates.length === 0) {
      candidates.push(JSON.stringify(ti).slice(0, 200));
    }
  }

  return [String(tool), candidates[0] ?? ""];
}

function formatResponse(format: string, decision: string, hookEventName: string): string {
  if (format === "claude-code") {
    const mapped = decision === "allow" ? "allow" : decision === "deny" ? "deny" : "ask";
    return JSON.stringify({
      hookSpecificOutput: { hookEventName, permissionDecision: mapped },
    });
  }
  // Cursor format.
  if (decision === "deny") {
    return JSON.stringify({
      permission: "deny",
      user_message: "Denied from your buddy client.",
      agent_message: "User denied this tool call via the buddy mobile/web app.",
    });
  }
  if (decision === "allow") {
    return JSON.stringify({ permission: "allow" });
  }
  return JSON.stringify({ permission: "ask" });
}

function fallbackResponse(format: string, hookEventName: string): string {
  return formatResponse(format, "ask", hookEventName);
}

function writeAndExit(json: string): void {
  process.stdout.write(json);
  process.exit(0);
}
