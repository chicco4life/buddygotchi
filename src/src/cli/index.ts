/**
 * CLI entry point. Routes to subcommands.
 */

import { VERSION } from "../outputs/web.js";

const command = process.argv[2];

switch (command) {
  case "daemon":
    await import("./daemon.js").then((m) => m.default());
    break;
  case "hook":
    await import("./hook.js").then((m) => m.default());
    break;
  case "signal":
    await import("./signal.js").then((m) => m.default());
    break;
  case "install":
    await import("./install.js").then((m) => m.default());
    break;
  case "version":
  case "--version":
  case "-v":
    console.log(`buddygotchi ${VERSION}`);
    break;
  default:
    console.error(`Usage: buddygotchi <daemon|hook|signal|install|version>`);
    if (command) console.error(`Unknown command: ${command}`);
    process.exit(1);
}
