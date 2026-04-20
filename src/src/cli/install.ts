/**
 * `buddygotchi install` — registers hooks in Claude Code settings.
 *
 * Adds a PreToolUse hook entry to ~/.claude/settings.json that points
 * to `buddygotchi hook --format claude-code`.
 */

import { readFileSync, writeFileSync, existsSync, mkdirSync } from "fs";
import { join } from "path";

export default async function install(): Promise<void> {
  const home = process.env.HOME ?? process.env.USERPROFILE ?? "/tmp";
  const claudeDir = join(home, ".claude");
  const settingsPath = join(claudeDir, "settings.json");

  // Find the buddygotchi binary path.
  const binaryPath = process.execPath;
  const hookCommand = `${binaryPath} hook --format claude-code`;

  // Load or create settings.
  let settings: Record<string, unknown> = {};
  if (existsSync(settingsPath)) {
    try {
      settings = JSON.parse(readFileSync(settingsPath, "utf-8"));
    } catch {
      console.error(`Warning: could not parse ${settingsPath}, creating fresh`);
    }
  } else {
    if (!existsSync(claudeDir)) {
      mkdirSync(claudeDir, { recursive: true });
    }
  }

  // Ensure hooks.PreToolUse array exists.
  if (!settings.hooks || typeof settings.hooks !== "object") {
    settings.hooks = {};
  }
  const hooks = settings.hooks as Record<string, unknown>;

  if (!Array.isArray(hooks.PreToolUse)) {
    hooks.PreToolUse = [];
  }
  const preToolUse = hooks.PreToolUse as Array<Record<string, unknown>>;

  // Check if already installed.
  const alreadyInstalled = preToolUse.some((entry) => {
    if (entry.type === "command" && typeof entry.command === "string") {
      return entry.command.includes("buddygotchi hook");
    }
    return false;
  });

  if (alreadyInstalled) {
    console.log("buddygotchi hook is already registered in Claude Code settings.");
    return;
  }

  // Add the hook.
  preToolUse.push({
    type: "command",
    command: hookCommand,
  });

  writeFileSync(settingsPath, JSON.stringify(settings, null, 2) + "\n", "utf-8");
  console.log(`Registered buddygotchi hook in ${settingsPath}`);
  console.log(`Hook command: ${hookCommand}`);
  console.log("\nRestart Claude Code for the hook to take effect.");
}
