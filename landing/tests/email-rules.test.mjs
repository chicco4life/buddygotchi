import { test } from "node:test";
import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";

const projectRoot = new URL("../", import.meta.url);
const repoRoot = new URL("../../", import.meta.url);
const emailsDir = new URL("emails/", repoRoot);
const copyRules = readFileSync(new URL("tests/copy-rules.test.mjs", projectRoot), "utf8");
const bannedSource = copyRules.match(/const BANNED = \[([\s\S]*?)\];/);
const banned = bannedSource ? [...bannedSource[1].matchAll(/"([^"]+)"/g)].map((match) => match[1]) : [];

function parseEmail(raw) {
  const match = raw.match(/^---\r?\n([\s\S]*?)\r?\n---\r?\n\r?\n?([\s\S]*)$/);
  assert.ok(match, "email template must have markdown frontmatter");

  const subject = match[1]
    .split(/\r?\n/)
    .find((line) => line.startsWith("subject: "))
    ?.slice("subject: ".length);
  assert.ok(subject, "email template must have a subject");

  return `${subject}\n${match[2]}`;
}

test("email templates follow brand law", () => {
  const files = readdirSync(emailsDir).filter(
    (file) => file.endsWith(".md") && readFileSync(new URL(file, emailsDir), "utf8").startsWith("---\n"),
  );
  assert.ok(files.length > 0, "expected at least one email template");

  for (const file of files) {
    const text = parseEmail(readFileSync(new URL(file, emailsDir), "utf8"));
    assert.ok(!text.includes("!"), `exclamation mark found in ${file}`);

    for (const word of banned) {
      const re = new RegExp(word.replace(/[-]/g, "\\-"), "i");
      assert.ok(!re.test(text), `banned word found in ${file}: ${word}`);
    }
  }
});

test("generated email templates are in sync", () => {
  const result = spawnSync(process.execPath, ["scripts/emails-build.mjs", "--check"], {
    cwd: projectRoot,
    encoding: "utf8",
  });

  assert.equal(result.status, 0, result.stderr || result.stdout);
});

test("waitlist confirmation renders clean text and minimal html", async () => {
  const { renderWaitlistConfirmation } = await import("../src/lib/email.ts");
  const rendered = renderWaitlistConfirmation({ position: 42, price: 119 });

  assert.ok(!rendered.subject.includes("{{"), "subject has leftover placeholder");
  assert.ok(!rendered.text.includes("{{"), "text has leftover placeholder");
  assert.ok(!rendered.html.includes("{{"), "html has leftover placeholder");
  assert.ok(!/<img\b/i.test(rendered.html), "html must not include images");
  assert.ok(rendered.text.startsWith("You're in line."), "text opens with the heading");
  assert.ok(/<h1[^>]*>You're in line\.<\/h1>/.test(rendered.html), "html has the heading");
  assert.ok(
    rendered.html.includes('<span style="color:#c9862b;font-weight:600;">#42</span>'),
    "html highlights the buddy number in amber",
  );
  assert.ok(
    rendered.html.includes('<a href="https://adoptaboop.com" style="color:#c9862b;'),
    "html links the sign-off domain in amber",
  );
});
