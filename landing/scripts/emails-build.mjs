import { existsSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { basename } from "node:path";
import process from "node:process";

const emailsDir = new URL("../emails/", import.meta.url);
const outFile = new URL("../src/lib/email-templates.ts", import.meta.url);
const check = process.argv.includes("--check");

function parseTemplate(fileUrl) {
  const raw = readFileSync(fileUrl, "utf8");
  const match = raw.match(/^---\r?\n([\s\S]*?)\r?\n---\r?\n\r?\n?([\s\S]*)$/);
  if (!match) {
    throw new Error(`${basename(fileUrl.pathname)} is missing markdown frontmatter`);
  }

  const frontmatter = {};
  for (const line of match[1].split(/\r?\n/)) {
    const field = line.match(/^([A-Za-z][A-Za-z0-9]*):\s*(.*)$/);
    if (!field) {
      throw new Error(`${basename(fileUrl.pathname)} has invalid frontmatter line: ${line}`);
    }
    frontmatter[field[1]] = field[2];
  }

  for (const key of ["id", "subject", "from", "replyTo", "trigger", "placeholders"]) {
    if (!frontmatter[key]) {
      throw new Error(`${basename(fileUrl.pathname)} is missing frontmatter field: ${key}`);
    }
  }

  return {
    id: frontmatter.id,
    subject: frontmatter.subject,
    from: frontmatter.from,
    replyTo: frontmatter.replyTo,
    trigger: frontmatter.trigger,
    placeholders: frontmatter.placeholders
      .split(",")
      .map((placeholder) => placeholder.trim())
      .filter(Boolean),
    heading: frontmatter.heading ?? "",
    subline: frontmatter.subline ?? "",
    body: match[2],
  };
}

function generate() {
  if (!existsSync(emailsDir)) {
    throw new Error(`Email template directory not found: ${emailsDir.pathname}`);
  }

  const templates = readdirSync(emailsDir)
    .filter((file) => file.endsWith(".md"))
    .filter((file) => readFileSync(new URL(file, emailsDir), "utf8").startsWith("---\n"))
    .sort()
    .map((file) => parseTemplate(new URL(file, emailsDir)));

  const body = templates.map((template) => `  ${JSON.stringify(template.id)}: ${JSON.stringify(template, null, 2)
    .split("\n")
    .join("\n  ")},`).join("\n");

  return `// GENERATED — edit emails/*.md then \`npm run emails:build\`

export const EMAIL_TEMPLATES = {
${body}
};

export const WAITLIST_CONFIRMATION_TEMPLATE = EMAIL_TEMPLATES["waitlist-confirmation"];
`;
}

const generated = generate();

if (check) {
  const current = existsSync(outFile) ? readFileSync(outFile, "utf8") : "";
  if (current !== generated) {
    console.error("landing/src/lib/email-templates.ts is out of sync. Run `npm run emails:build`.");
    process.exit(1);
  }
  process.exit(0);
}

writeFileSync(outFile, generated);
