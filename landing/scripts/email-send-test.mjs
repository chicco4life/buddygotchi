import { existsSync, readFileSync } from "node:fs";
import process from "node:process";

function loadDotenvLocal() {
  const path = new URL("../.env.local", import.meta.url);
  if (!existsSync(path)) return;

  const lines = readFileSync(path, "utf8").split(/\r?\n/);
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;

    const match = trimmed.match(/^([A-Za-z_][A-Za-z0-9_]*)=(.*)$/);
    if (!match) continue;

    const [, key, rawValue] = match;
    if (process.env[key] !== undefined) continue;

    let value = rawValue.trim();
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }
    process.env[key] = value;
  }
}

loadDotenvLocal();

const to = process.argv[2];
if (!to) {
  console.error("Usage: npm run email:test -- you@example.com");
  process.exit(1);
}

const { sendWaitlistConfirmation } = await import("../src/lib/email.ts");
const result = await sendWaitlistConfirmation({
  to,
  position: 42,
  price: 119,
});

if (result.status === "sent") {
  console.log(`Sent waitlist confirmation: ${result.id ?? "no id returned"}`);
} else {
  console.error(`Email send failed: ${result.reason ?? result.error}`);
  process.exitCode = 1;
}
