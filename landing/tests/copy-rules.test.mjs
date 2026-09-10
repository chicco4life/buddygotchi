import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

/*
  Brand law as a unit test (SPEC.md §10). Scans the raw copy source so it catches
  future edits, no build/transpile needed.
*/
const src = readFileSync(new URL("../src/lib/copy.ts", import.meta.url), "utf8");

// Only the string literals — so code (comments, keys, `as const`) can't trip it.
const strings = [...src.matchAll(/"((?:[^"\\]|\\.)*)"/g)].map((m) => m[1]).join("\n");

const BANNED = [
  "revolutionary",
  "supercharge",
  "AI-powered",
  "game-changer",
  "productivity",
  "premium",
];

test("copy contains no banned hype words", () => {
  for (const word of BANNED) {
    const re = new RegExp(word.replace(/[-]/g, "\\-"), "i");
    assert.ok(!re.test(strings), `banned word found in copy: ${word}`);
  }
});

test("copy contains no exclamation marks", () => {
  assert.ok(!strings.includes("!"), "exclamation mark found in copy strings");
});
