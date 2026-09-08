# Emails

The canonical home of every email Boop sends. One markdown file per email;
the plain-text body in the file **is** the template (MARKETING.md §3.6: short,
honest, zero images; trust compounds from the first touch). At send time the
landing app renders the same content into an HTML version styled like the
landing page — cream `#f7f2e9`, charcoal `#2b2724`, one amber accent, big
sentence-case heading, still zero images and no tracking pixel (deliberate:
deliverability and the privacy promise).

## Format

Each email is a single `.md` file:

```markdown
---
id: kebab-case-identifier
subject: Subject line, may use {{placeholders}}
from: Boop Computer <hello@adoptaboop.com>
replyTo: hello@adoptaboop.com
trigger: what causes this send, and from where in the code
placeholders: comma, separated, list
heading: Large headline in the HTML version; first line of the text version
subline: Supporting line under the heading (optional)
---

body paragraphs with {{placeholders}}, ending with the sign-off:

Boop Computer
adoptaboop.com
```

The plain-text version is `heading + subline + body`; the HTML version sets
the heading large, highlights `#{{position}}` in amber, and styles the last
paragraph (the sign-off) as a quiet footer.

Brand law applies to subject and body exactly as it does to site copy
(`landing/tests/copy-rules.test.mjs`): no exclamation marks, no hype words
(revolutionary, supercharge, AI-powered, game-changer, productivity, premium).
Emails additionally ban em-dashes (—) everywhere, including the subject —
use periods, commas, or colons instead (enforced by
`landing/tests/email-rules.test.mjs`).
Sentence case, matching the site's copy register — warm, dry, specific.
Sender is always "Boop Computer" (the lockup, per MARKETING.md §1.5); the
in-universe vocabulary (Founding Litter, hatches, buddy) lives in the words,
not the sender name.

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
  must work before any send (archived/research/TODOs.md).
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
