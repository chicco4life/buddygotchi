# Emails

The canonical home of every email Boop sends. One markdown file per email;
the plain-text body in the file **is** the template — by design there is no
rich-HTML layer to maintain (MARKETING.md §3.6: in-universe, one paragraph,
zero images; trust compounds from the first touch). At send time the landing
app wraps the same text in a minimal HTML shell (cream background, charcoal
text, no images) purely so it renders comfortably in HTML-first clients.

## Format

Each email is a single `.md` file:

```markdown
---
id: kebab-case-identifier
subject: Subject line, may use {{placeholders}}
from: The Litter <hello@adoptaboop.com>
replyTo: hello@adoptaboop.com
trigger: what causes this send, and from where in the code
placeholders: comma, separated, list
---

plain-text body with {{placeholders}}
```

Brand law applies to subject and body exactly as it does to site copy
(`landing/tests/copy-rules.test.mjs`): no exclamation marks, no hype words
(revolutionary, supercharge, AI-powered, game-changer, productivity, premium),
lowercase-hearted, dry, in-universe. Every email is signed "— The Litter".

## Workflow

The landing app cannot import from this directory at runtime (its Vercel
project root is `landing/`), so templates are embedded by a build step:

1. Edit the `.md` file here.
2. `cd landing && npm run emails:build` — regenerates
   `landing/src/lib/email-templates.ts` (a generated file; never edit it by hand).
3. Commit both files. A unit test fails if they drift out of sync.

Test-send a rendered sample through Resend (uses `RESEND_API_KEY` from
`landing/.env.local`):

```sh
cd landing && npm run email:test -- you@example.com
```

## Sending infrastructure

- Provider: Resend, domain `adoptaboop.com` (verified: SPF + DKIM).
- Env: `RESEND_API_KEY` (Vercel project env + `landing/.env.local`). Unset →
  sending is silently skipped; a missing key must never break a signup
  (fail-open, like everything else in this project).
- Replies go to `hello@adoptaboop.com` — inbound forwarding for that address
  must work before any send (research/TODOs.md).
- Add a DMARC record once sends begin (`p=none` to start) if not already set.
- The waitlist confirmation is transactional (no unsubscribe link needed; the
  body offers "reply to leave" in plain language, which is better anyway).
  Any future *broadcast* (batch-two announcement, "adoptions open") must add a
  List-Unsubscribe header / Resend audience — do not reuse the transactional
  path for those.

## Emails

| id | trigger | status |
| --- | --- | --- |
| `waitlist-confirmation` | first successful waitlist signup | live |
| `number-came-up` | adoption opens for a signup's number | planned — written when a manufacturing date is confident |
| `batch-two-announcement` | Founding Litter sells out | planned (broadcast — needs unsubscribe) |
