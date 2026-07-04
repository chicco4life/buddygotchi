# Buddygotchi Landing Page — Technical Specification

Status: implemented; media strategy amended — see Amendment A (§14); section/copy revisions — see Amendment B (§15)
Last updated: 2026-07-03
Source documents: `../docs/MARKETING.md` (Part 2 is the marketing-side page spec; Part 3 is the demand test this page powers), `../docs/PRODUCT.md` (§9 form factor, §11 positioning, §12 agent-era value prop)

This document is self-contained: an implementing agent should be able to build the entire site from this file alone. Where this spec and `../docs/MARKETING.md` conflict, `../docs/MARKETING.md` wins on copy and brand; this spec wins on technology.

---

## 1. What this is and why it exists

A single-page marketing site for Buddygotchi — a physical desk companion (a wobbling, glowing blob) that surfaces AI coding-agent state and lets you approve tool calls by petting it. The page has exactly one job: convert a visitor into a **waitlist email signup** (optionally with UTM/price-cohort metadata) for the "Founding Litter" of 100 units, in support of a paid-traffic demand test.

Success criteria, in order:

1. A visitor emotionally "gets it" within 10 seconds of landing (hero video + three-word headline).
2. Email capture works reliably and records the attribution metadata the demand test needs (UTM params, price cohort, referrer).
3. The page *feels* premium — which per the brand rules means restraint: one typeface, enormous whitespace, no conversion-tactic clutter.
4. Lighthouse performance ≥ 90 on mobile; the page is mostly static and must be fast on hotel wifi.

Explicit non-goals: no blog, no CMS, no checkout/payments, no user accounts, no nav menu, no multi-page IA. One page, one modal, one confirmation page.

---

## 2. Repo placement and project layout

The landing page lives in `landing/` at the top level of the `buddygotchi` repo, as a fully independent project. Nothing in `landing/` may import from or depend on the rest of the repo. The existing structure already isolates the other products — `app/` is the Swift macOS app, `firmware/esp32/` is firmware — so no existing directories move. Do not touch anything outside `landing/`.

```
buddygotchi/
├── app/                  # Swift macOS app
├── landing/              # Next.js landing page
│   ├── SPEC.md           # this file
│   ├── package.json
│   ├── next.config.ts
│   ├── vercel.json
│   ├── tsconfig.json
│   ├── postcss.config.mjs
│   ├── .env.example
│   ├── public/
│   │   ├── media/        # generated mock media / future photo and video assets
│   │   ├── logos/        # agent compatibility marks (see §8.3)
│   │   └── og.jpg
│   └── src/
│       ├── app/
│       │   ├── layout.tsx        # fonts, metadata, analytics
│       │   ├── page.tsx          # the landing page (sections S1–S8)
│       │   ├── welcome/page.tsx  # post-signup page (§6.3)
│       │   ├── privacy/page.tsx  # short plain-language privacy note
│       │   └── api/waitlist/route.ts
│       ├── components/           # one file per section + shared primitives
│       ├── lib/                  # db.ts, attribution.ts, copy.ts
│       └── styles/globals.css    # design tokens as CSS variables + Tailwind
├── firmware/esp32/       # ESP32 firmware
├── docs/                 # plans, specs, architecture, references
└── ...
```

Copy lives centralized in `src/lib/copy.ts` (a typed constant object), not scattered through JSX — the copy will be A/B-tweaked during the test and must be editable in one place.

---

## 3. Technology stack

Chosen for: first-class Vercel support, popularity/agent-friendliness, and minimal moving parts.

| Concern | Choice | Notes |
|---|---|---|
| Framework | **Next.js 15+ (App Router, TypeScript)** | `create-next-app` defaults. Static-first: the page itself is a static/ISR route; only the waitlist API is dynamic. |
| Styling | **Tailwind CSS v4** | Design tokens defined as CSS variables in `globals.css`, referenced via Tailwind theme. No component library — the page is bespoke and small; a UI kit would fight the design language. |
| Fonts | **Geist Sans via `next/font`** | A modern grotesque (per brand), zero-config in Next, self-hosted automatically. Two weights only: 400 and 600. No other families anywhere. |
| Database | **Neon Postgres via Vercel Marketplace** (`@neondatabase/serverless`) | One table (§7.1). Plain SQL, no ORM — the schema is one table and an ORM is overhead. |
| Email validation | `zod` on the API route | Syntactic validation + lowercase/trim normalization. No verification emails in v1. |
| Analytics | **Vercel Analytics** (`@vercel/analytics`) + custom events | Plus env-gated ad pixels for the demand test (§7.3). |
| Animation | CSS transitions + a single `IntersectionObserver` reveal hook | **No animation library.** The motion spec (§4.4) is achievable with CSS alone; framer-motion's spring defaults violate the "no overshoot" rule. |
| Testing | `next lint`, `tsc --noEmit`, one Playwright spec (§12) | Keep it light. |
| Package manager | npm | Boring and universal. |

No CMS, no i18n, no dark mode toggle (the page's palette *is* the product's palette; there is one deliberate dark section, S4/night imagery, but the page itself does not theme-switch).

---

## 4. Design system

The governing idea from `../docs/MARKETING.md` §1.3: premium is restraint. Processing fluency = perceived quality. When in doubt, remove.

### 4.1 Color tokens

The palette is the physical product's palette — cream shell, warm charcoal, amber attention glow. Define in `globals.css`:

```css
:root {
  --cream: #F7F2E9;        /* page background — matches the blob's "Mochi" shell */
  --cream-deep: #EFE7D8;   /* subtle alt-surface (modal, input fills). Use sparingly. */
  --charcoal: #2B2724;     /* primary text — warm, never pure black */
  --charcoal-soft: #6E675D;/* secondary text, captions */
  --amber: #E8A33D;        /* the attention glow. CTA buttons, focus rings, accents */
  --amber-deep: #C9862B;   /* CTA hover/pressed */
  --green: #7FA96B;        /* the "approved" ripple — used only in S1/S3 contexts, never as UI chrome */
  --night: #1B1714;        /* background of the one dark scene (S4 strip / night photo) */
  --night-text: #EFE7D8;   /* text on --night */
}
```

Rules: no gradients on text; no pure white (`#FFF`) or pure black anywhere; the green is imagery/accent vocabulary, not a "success state" UI color — form success states use charcoal text with an amber accent. Borders are avoided entirely (separation by whitespace); where an edge is unavoidable (input fields), use `--charcoal` at 15% opacity.

### 4.2 Typography

- Family: Geist Sans everywhere. Weights 400 and 600 only.
- Hero headline: `clamp(2.75rem, 7vw, 5.5rem)`, weight 600, tracking `-0.02em`, line-height 1.05.
- Section headlines: `clamp(1.75rem, 3.5vw, 2.5rem)`, weight 600.
- Body: 1.125rem / line-height 1.6, weight 400, `--charcoal`.
- Captions/small print: 0.875rem, `--charcoal-soft`.
- Tiny labels (the only permitted ALL CAPS): 0.75rem, tracking `0.08em`, weight 600 — used for things like `FOUNDING LITTER · 100 NUMBERED BUDDIES`.
- No italics except the wry one-liners quoted from copy; no text shadows; no exclamation marks in any string, ever (enforced by a lint-style unit test on `copy.ts` if convenient).

### 4.3 Layout

- Content max-width: **1100px**, centered, `px-6` on mobile.
- Vertical rhythm: **minimum 120px** between sections (`py-16 md:py-24` at minimum; more is fine). Sections are separated by space alone — no cards, borders, rules, or background-color alternation (the single `--night` passage is the one exception).
- The poster test (from `../docs/MARKETING.md` §2.3): a screenshot of any full viewport at any scroll position should look like a poster, not a website. Practically: one idea per viewport; if two sections are visible at once on desktop, add space.
- Fully responsive; design mobile-first — the ad traffic (Reddit/X/IG) is majority mobile. The three-across still/loop rows (S2, S3) stack vertically on mobile with generous spacing.

### 4.4 Motion

Every animation obeys the physics of the physical blob: eased, damped, slow, never bouncy.

- Easing: `cubic-bezier(0.22, 1, 0.36, 1)` (ease-out-quint feel, no overshoot). Never use spring/bounce curves.
- Durations: 500–800ms for reveals; nothing under 300ms except hover states (150ms).
- Scroll reveal: sections fade up 16–24px with the above easing, triggered once via one shared `IntersectionObserver` hook (`useReveal`). Subtle — opacity 0→1, translate only. No parallax, no scroll-jacking, no sticky theatrics.
- Videos: autoplay, muted, loop, `playsInline`, no controls. **All silent.** There is no sound anywhere on this page in v1 (the marketing plan's "one labeled turn-sound-on moment" is deferred until real audio assets exist).
- `prefers-reduced-motion: reduce` → all reveals render instantly, videos still autoplay (they are ambient content, not motion effects) but the CSS glow pulse (§5 S1 placeholder) freezes.

### 4.5 The CTA button (one style, used twice)

Pill-shaped, `--amber` background, `--charcoal` text, weight 600, generous padding (`px-8 py-4`), soft warm shadow (`0 8px 24px rgb(232 163 61 / 0.35)`). Hover: `--amber-deep`, shadow tightens, 150ms. This exact button is used for the hero CTA and the footer email submit — nothing else on the page is amber-filled, so the eye always knows what to do.

---

## 5. Page structure: sections S1–S8

One page, **no header, no nav** — nothing to do but scroll and one thing to click. Copy below is final-draft quality from `../docs/MARKETING.md` §2.2; implement it verbatim (register: lowercase-hearted, dry, specific). Each section is its own component in `src/components/`.

### S1 — Hero (100vh)

- Full-bleed, full-viewport-height. Media: autoplaying muted loop (~12s) — blob idling on a real desk in warm light, glow shifts amber, a hand enters and *pets* it, happy squint, green ripple, hand returns to keyboard. Asset: `public/media/hero-loop.mp4` (placeholder until shoot; see §8).
- Text block over the **lower third**, left-aligned within the 1100px column, with a subtle cream scrim behind it for legibility (`linear-gradient(transparent, rgb(247 242 233 / 0.9))` bottom third — over the placeholder this reads as part of the design).
  - Headline: **Approve with a pet.**
  - Subhead: *A little creature that watches your AI agents — and only bothers you when it matters.*
  - CTA button: **Adopt one — $119** (price is cohort-dependent, §7.2; clicking opens the waitlist modal, §6.1)
  - Small text under the button (tiny-label style): `Founding Litter · 100 numbered buddies · no subscription, ever`
- No scroll-hint chevron, no header logo. The wordmark "Buddygotchi" appears only in the footer and metadata.

### S2 — The moment (the alibi, shown not told)

Three stills in a row (stack on mobile), minimal captions beneath each:

1. Amber glow, screen shows `▸ claude wants to run npm test` — caption: **It asks.**
2. Hand mid-pet, blob squinting — caption: **You pet.**
3. Wide shot, human back at work, blob content — caption: **Everyone gets back to work.**

One line below the row, centered, secondary color: *Permission prompts, completions, and failures — surfaced as a feeling in the corner of your eye, not another notification.*

### S3 — It's alive

Three short video loops in a horizontal band (lazy-loaded; stack on mobile). Captions in the wry register:

1. The wobble — *Boop it. It forgives you.*
2. The sleep peek — *It sleeps when your agents do.*
3. The celebration — *It's genuinely proud of your build passing.*

### S4 — The light language

A single elegant horizontal strip on the `--night` background (full-bleed band, the page's one dark passage): five blob silhouettes with their glows — working (warm breathing), needs-you (amber), done (green ripple), stuck (dim red heartbeat), asleep (dark). Implement as one SVG/CSS composition (`LightLanguage.tsx`) — five rounded-blob shapes with radial-gradient glows and slow CSS keyframe pulses (4s breathing period; everything slow and soft). Tiny labels under each. One caption line: *You'll learn its moods in a day. Amber means come here. Everything else means you're free.*

This section is deliberately built rather than photographed — it's a diagram, and the one place CSS art is on-brand.

### S5 — The rational floor (compatibility + trust)

Restrained, small type. Two rows:

- Compatibility row: **Claude Code · Codex · Cursor · VS Code** — rendered as text wordmarks in `--charcoal-soft` (see §8.3 on logos), with caption: *Speaks fluent agent. One-click setup from the Mac app.*
- Three trust lines (three columns desktop, stacked mobile), each a bold lead-in + one sentence:
  - **Local-first** — *everything runs on your Mac; the buddy talks to it over Bluetooth. No cloud, no account.*
  - **No subscription** — *buy it once. When agents change, it learns new tricks in free updates.*
  - **USB-C powered** — *lives on your desk, plugged in, always on.*

No icons unless truly tiny and monochrome; text alone is acceptable and safer.

### S6 — The craft

Two-column (image left, copy right; stacked mobile). Image: exploded-view render — shell, screen, silicone crown, steel disc, base ring floating apart (`public/media/exploded.jpg`; the one acceptable render). Copy beside it, sparse, set as four standalone lines with breathing room:

> *A frosted shell that glows from within.*
> *A steel heart, so it always rights itself — 162 grams of calm.*
> *A silicone crown that clicks like a marshmallow.*
> *Two buttons. That's all it needs.*

### S7 — FAQ

Five questions, one-line answers, plain stacked text (question weight 600, answer weight 400 in `--charcoal-soft`). **No accordion** — collapsing five lines is disfluency for no gain.

- *Does it need a subscription?* — No. Never.
- *What does it actually do?* — Shows what your agents are doing, glows when one needs you, lets you approve or deny with a press, celebrates when work lands.
- *What if I auto-approve everything?* — Then it's the thing that tells you when to come back. That's most of the point.
- *What about my code and data?* — The buddy sees state, not source. Everything stays on your machine.
- *Mac only?* — For now. The buddy doesn't judge.

Add FAQ JSON-LD (`FAQPage` schema) in this section — free SEO for the only structured content on the page.

### S8 — Footer

- Inline email capture: single email input + the amber CTA button labeled **Get in line** (same endpoint as the modal, source tagged `footer`).
- Tiny links: `privacy` (route `/privacy` — a few plain paragraphs: we store your email and the campaign link you arrived from, we email you about the Founding Litter, unsubscribe anytime, nothing is sold) and `contact` (mailto).
- Sign-off line, small, secondary: *Made by people who also forgot a task finished 40 minutes ago.*
- Wordmark: `Buddygotchi` tiny-label style. Copyright line. That's all.

### Deliberate omissions (do not add these)

No comparison table, no specs block, no testimonials, no press logos, no countdown timers, no exit-intent popups, no chat widget, no cookie banner theatrics (see §7.3 — analytics are cookieless), no social icons, no "as seen on." Each is a conversion tactic that costs premium perception more than it gains.

---

## 6. Interactive flows

### 6.1 Waitlist modal (the honest "out of stock" state)

Clicking the hero CTA opens a modal (accessible: focus-trapped, `Esc`/backdrop closes, focus returns to trigger; use the native `<dialog>` element):

- Heading: **The Founding Litter of 100 is being hand-assembled now.**
- Body: *Leave your email to claim a place in line — first come, first adopted.*
- Email field (labeled, `type="email"`, `autocomplete="email"`) + amber button: **Get in line**
- Small text: `No spam. One email when your number comes up.`

Submit → `POST /api/waitlist` → on success, close modal and client-navigate to `/welcome?pos=N&code=XYZ`. On error: inline message in-register (*Something hiccuped. Try once more?*), never a toast library. Duplicate email → treat as success and route to `/welcome` with their existing position (idempotent).

### 6.2 API: `POST /api/waitlist`

Request body: `{ email: string, source: 'hero' | 'footer' }`. Server-side:

1. Validate/normalize email with zod (trim, lowercase).
2. Read attribution from cookies (§7.2): utm params, price cohort, referrer, `ref` code, landing timestamp.
3. Insert (or fetch on conflict) into `signups` (§7.1). Generate an 8-char base32 referral code.
4. Compute position: `row_number over created_at` minus `10 × referral_count` (floor 1).
5. Return `{ position, referralCode }`.

Basic abuse guard: reject >5 requests/minute per IP (in-memory map is fine at this traffic level; note the limitation in a comment). No email sending in v1 — the autoresponder is a follow-up task and needs an email provider decision.

### 6.3 `/welcome` — the post-signup page (peak–end rule: this page matters)

Same design system, one viewport:

- Heading: **You're in line.** Subline: *Buddy #{position} will be yours when the Founding Litter hatches.*
- A small hatching-egg vignette: a simple SVG egg with a slow CSS crack-and-peek animation (10–15 lines of SVG; keep it damped and slow, in-register with §4.4).
- Share hook: *Want to skip ahead? Every friend who joins moves you up 10 places.* Below: a read-only input with `https://<domain>/?ref={code}` and a **Copy link** button (clipboard API, button text flips to `Copied` for 2s — no exclamation mark).
- Nothing else. No deposit ask in v1 (`../docs/MARKETING.md` §2.4's $5 deposit is a deliberate later variant).

Direct visits to `/welcome` without params render a graceful generic version ("You're in line. Watch your inbox.").

---

## 7. Data, attribution, and analytics (the demand test depends on this)

### 7.1 Database schema (Neon Postgres)

```sql
create table if not exists signups (
  id            bigint generated always as identity primary key,
  email         text not null unique,
  source        text not null,              -- 'hero' | 'footer'
  price_cohort  integer,                    -- 99 | 129 | null (default $119 shown)
  utm_source    text, utm_medium text, utm_campaign text, utm_content text, utm_term text,
  referrer      text,                       -- document.referrer at landing
  ref_code_used text,                       -- ?ref= code they arrived with
  referral_code text not null unique,       -- their own share code
  referral_count integer not null default 0,
  created_at    timestamptz not null default now()
);
```

Ship the DDL as `landing/db/schema.sql` plus an npm script `db:push` that applies it (`psql $DATABASE_URL -f db/schema.sql` or a tiny node script using the Neon driver). When a signup arrives with `ref_code_used`, increment that referrer's `referral_count` in the same transaction.

### 7.2 Attribution capture (client)

A tiny `attribution.ts` module runs once on first load: read `utm_*`, `p` (price cohort), and `ref` from `location.search` plus `document.referrer`, and persist to a single first-party cookie (`bg_attr`, JSON, 30-day expiry, `SameSite=Lax`) — **only setting values on first touch** so later organic revisits don't overwrite the paid-channel attribution. The API route reads this cookie server-side.

Price cohort: `?p=99` or `?p=129` (the test skips $119 per `../docs/MARKETING.md` §3.3). The displayed CTA price renders from the cohort — `Adopt one — $99/119/129` — via a client component that reads the cookie; default $119 when absent. The page stays static; only the price span hydrates.

### 7.3 Analytics and events

- **Vercel Analytics** for page views and Web Vitals (cookieless — no consent banner needed).
- Custom events via `track()`: `cta_click` (hero|footer), `modal_open`, `signup` (with source + cohort), `copy_referral`.
- **Scroll depth**: fire `scroll_depth` events at each section boundary (S1…S8) using the existing `IntersectionObserver` hook — this is how the test finds where interest dies (`../docs/MARKETING.md` §3.3).
- **Ad pixels**, env-gated and loaded only when the corresponding ID is set: `NEXT_PUBLIC_REDDIT_PIXEL_ID`, `NEXT_PUBLIC_TWITTER_PIXEL_ID`, `NEXT_PUBLIC_META_PIXEL_ID`. Each fires its standard PageView on load and a Lead/SignUp conversion on the `signup` event. Load via `next/script` `strategy="afterInteractive"`, wrapped in one `Pixels.tsx` component so it's removable in one place. With no IDs set (local dev, pre-test), zero third-party script bytes load.

---

## 8. Assets: manifest and placeholder strategy

**No final photography or video exists yet.** The site must be built and deployable now, with real assets dropped in later by filename swap — no code changes.

### 8.1 Placeholder system

Build a `Media` component: `<Media src="/media/hero-loop.mp4" poster="/media/hero-poster.jpg" ratio={16/9} alt="..." shotNote="Blob on desk, amber glow, hand pets it" />`. It renders the real file if present at build/runtime; the committed placeholder files are **art-directed stand-ins generated in code and exported to `public/media/`**: warm cream-to-amber radial gradients with a soft blob silhouette (simple SVG-rendered shapes matching §9.1 of `../docs/PRODUCT.md`: squashed sphere, wider than tall, screen-face slightly above midline, two blush dots) and the shot note in tiny caption type in a corner. They should look intentional — a person landing on the deployed placeholder site should read "tasteful pre-launch," not "broken images." For video slots, the placeholder is the poster image with a slow CSS glow-breathing overlay (4s period).

### 8.2 Asset manifest (final files, exact names)

| File | Section | Spec |
|---|---|---|
| `hero-loop.mp4` + `hero-poster.jpg` | S1 | ~12s loop, ≤ **4 MB**, H.264 1920×1080, muted, no audio track. Desk-eye level. |
| `moment-asks.jpg`, `moment-pet.jpg`, `moment-work.jpg` | S2 | 4:3 stills, ≤ 300 KB each (serve via `next/image`) |
| `alive-wobble.mp4`, `alive-sleep.mp4`, `alive-celebrate.mp4` + posters | S3 | 3–5s loops, ≤ 1.5 MB each, 1:1 or 4:5, lazy-loaded (`preload="none"`, IntersectionObserver-started) |
| `exploded.jpg` | S6 | 4:5 render, ≤ 400 KB |
| `og.jpg` | metadata | 1200×630 — night shot, amber glow, headline text baked in (placeholder version generated) |

Photography direction (for whoever shoots; keep in this file): real desk, morning side-light, wood + one plant, shallow depth of field, slight grain; blob at eye level or slightly below — **never from above** (shrinks the face, kills the baby-schema effect); hands in ⅔ of shots; one night scene with amber as the only warm source.

### 8.3 Compatibility logos

Do **not** ship third-party logo image files without checking each vendor's brand-use terms. V1 renders `Claude Code · Codex · Cursor · VS Code` as styled text wordmarks (Geist 600, `--charcoal-soft`, generous letter-spacing) — this reads as restraint, is legally clean, and matches the page. Leave a `logos/` directory and a TODO for approved marks.

---

## 9. SEO, metadata, accessibility, performance

### 9.1 Metadata

- `<title>`: `Buddygotchi — a desk companion for AI agents`
- Meta description: `A little creature that watches your AI coding agents — glows when one needs you, celebrates when work lands, and lets you approve with a pet. Founding Litter of 100.`
- The phrase **"desk companion for AI agents"** must appear in the title/description and once in body copy — we're naming the category (`../docs/PRODUCT.md` §11.7).
- OpenGraph + Twitter card (`summary_large_image`) with `og.jpg`; canonical URL; `robots: index, follow`; favicon: a tiny blob silhouette SVG (cream on charcoal).

### 9.2 Accessibility

Semantic landmarks (`main`, `section` with `aria-label`, one `h1`); the modal fully keyboard-operable; all media has `alt`/`aria-label` text describing the *content* ("a hand pets a small glowing creature; it squints happily"); color contrast: `--charcoal` on `--cream` is ~12:1 (fine), verify `--charcoal-soft` on `--cream` ≥ 4.5:1 and amber button text ≥ 4.5:1 (charcoal-on-amber passes); focus rings: 2px `--amber` offset ring, never removed.

### 9.3 Performance budget

- LCP ≤ 2.5s mobile: hero renders poster image immediately (`priority` next/image), video swaps in when loaded.
- JS: no client component larger than it must be; the page is ~90% server components. No animation lib, no form lib, no date lib.
- All images through `next/image`; S3 videos `preload="none"`; fonts subset by `next/font` automatically.
- Total transfer on first mobile view (before hero video finishes) ≤ 1 MB.

---

## 10. Copy and brand constraints (hard rules)

These are enforced brand law from `../docs/MARKETING.md` §1.3 — treat violations as bugs:

1. **Banned words:** revolutionary, supercharge, AI-powered, productivity, game-changer, premium. **Banned punctuation:** `!` anywhere in UI copy.
2. Concrete nouns and exact numbers over adjectives: "162 grams," "batch of 100," "under one second" — never "high quality," "blazing fast."
3. One wry line per screenful, maximum. Understatement over hype.
4. Stay in-universe: "adopt," "litter," "get in line," "hatches" — never "order," "purchase," "sign up for our newsletter," "submit."
5. Sentence case everywhere; ALL CAPS only in tiny labels.
6. Nothing fabricated: no fake counters, testimonials, or press. The counter component ships hidden (§5 S7).
7. Add a small unit test that scans `copy.ts` for banned words and `!` — cheap insurance against future edits.

---

## 11. Vercel deployment setup

### 11.1 One-time project setup

1. Push the repo to GitHub (it is the existing `buddygotchi` repo; `landing/` is a subdirectory of it).
2. In Vercel dashboard: **Add New → Project → import the `buddygotchi` repo.**
3. **Root Directory: `landing`** ← the critical monorepo setting. Framework preset auto-detects Next.js. Leave build/install commands default (`next build` / `npm install`).
4. Storage → **Create Database → Neon (Postgres)** via the Vercel Marketplace, link it to the project. This injects `DATABASE_URL` automatically. Run `npm run db:push` once locally against it (pull env first, §11.3).
5. Project → Analytics → **Enable Vercel Analytics**.
6. Environment variables (Production; see `.env.example`): `NEXT_PUBLIC_SHOW_COUNTER` (unset = hidden), and the three pixel IDs when the ad accounts exist (unset until then).
7. Domains: add `buddygotchi.com` (or chosen domain) + `www` redirect → apex. Vercel provisions TLS automatically.

### 11.2 Skip builds when only the Mac app changes

Since the repo also contains the Swift app and firmware, add to `landing/vercel.json` so pushes that don't touch `landing/` skip deployment:

```json
{
  "ignoreCommand": "git diff --quiet HEAD^ HEAD -- ."
}
```

(The command runs inside the Root Directory, so `.` means `landing/`. Exit 0 = skip build.)

### 11.3 Local development

```sh
cd landing
npm install
cp .env.example .env.local     # fill DATABASE_URL (or: npx vercel link && npx vercel env pull .env.local)
npm run db:push                # apply schema once
npm run dev                    # http://localhost:3000
```

`.env.example` documents every variable with a one-line comment. The app must boot with **no** env vars set: without `DATABASE_URL` the waitlist API returns a clear 503 and the page still renders (fail-open, like everything else in this project).

### 11.4 Deploy flow

Git-push deploys: every push to `main` touching `landing/` → production; PRs → preview URLs (use these for copy review). Manual escape hatch: `cd landing && npx vercel --prod`.

---

## 12. Scripts, testing, acceptance

`package.json` scripts: `dev`, `build`, `start`, `lint`, `typecheck` (`tsc --noEmit`), `test` (the copy-rules unit test, §10.7), `test:e2e` (Playwright), `db:push`.

One Playwright spec (`e2e/waitlist.spec.ts`) run against `next dev` with a stubbed DB (in-memory fallback when `DATABASE_URL` is unset in test mode): loads `/?p=99&utm_source=test`, asserts the CTA shows `$99`, opens the modal, submits an email, lands on `/welcome`, sees a position and a copyable referral link.

### Acceptance checklist (definition of done)

- [ ] `npm run build` clean; `lint`, `typecheck`, `test`, `test:e2e` all pass
- [ ] All nine sections present with copy verbatim from §5; no banned words, no `!`
- [ ] Placeholder media looks intentional at desktop and 375px mobile widths
- [ ] Waitlist flow works end-to-end against a real Neon DB, including duplicate-email idempotency and referral crediting
- [ ] `?p=99` / `?p=129` change the CTA price and are stored on the signup row; UTM params survive from landing → cookie → DB row
- [ ] Scroll-depth events fire per section; pixels load only when IDs are set
- [ ] Lighthouse mobile: Performance ≥ 90, Accessibility ≥ 95, SEO ≥ 95
- [ ] `prefers-reduced-motion` respected; modal keyboard-accessible
- [ ] Deploys on Vercel with Root Directory `landing`; `ignoreCommand` skips app-only pushes
- [ ] Counter hidden; no fabricated numbers anywhere

### Explicitly deferred (do not build in v1)

$5 deposit flow (needs Stripe — separate task after email capture is proven), the waitlist autoresponder email (needs provider decision), sound-on moment, real photography/video, CE/logo asset swaps, blog/build-in-public pages on the domain.

---

## 14. Amendment A (2026-07-03): asset-light redesign

The product does not exist yet, so the photo/video slots specified in §5/§8 cannot be filled — and a demand-test page full of labeled placeholders undercuts the premium read. This amendment supersedes the media strategy in §5 and §8; everything else (copy, section order, flows, data, brand law) stands.

**Media slot reduced to one**, intended for a generated mock image (manifest in `public/media/README.md`):

1. `hero.jpg` — S1, full-bleed. The money shot: blob on a desk, amber glow, hand mid-pet.

**Everything else is drawn, not photographed**, extending the built visual language S4 already used:

- A shared illustrated buddy (`src/components/BuddyBlob.tsx`, server component, zero client JS) with the product's real proportions (docs/PRODUCT.md §9.1) and expressions: content, alert, squint, sleep (with the one-eye peek), celebrate.
- **S2** — three drawn beats (amber-alert blob + terminal chip → petted squinting blob → contented blob) with the original captions.
- **S3** — three animated vignettes: the damped CSS wobble (`buddy-wobble`, 2–3 rocks then long stillness), the sleep peek (`buddy-peek-*`), and the confetti celebration (`buddy-twinkle`). All motion stays within §4.4's damped-physics rules and freezes under `prefers-reduced-motion`.
- **S6** — a hairline-labeled exploded diagram (crown / shell / screen / steel heart / base ring) in place of the render.
- The floating vignettes also remove the rounded media frames from S2/S3, which brings the page closer to the no-cards/no-borders rule (§4.3).

`Media.tsx` is image-only now; the video-capable version lives in git history (pre-Amendment-A) for when real film exists. Honesty rationale: drawn art makes no claim to be a photograph of a product that doesn't exist, while a page of "placeholder" frames or AI-faked photos would. When the product is real, S1/S3 return to film per §5 and this amendment retires.

---

## 15. Amendment B (2026-07-03): section and copy revisions

Business-review revisions. Where this conflicts with §5/§8 or `../research/product/MARKETING.md` §2.2, this amendment wins.

1. **S6 is now The adoption, not The craft.** The exploded-view/component section is removed on purpose — the internals stay ambiguous while the hardware is still being finalized. The adoption section (MARKETING.md §2.2 S7) is restored in its place, **without the care card** (dropped from the box contents). It shows a drawn open box (swap target: `public/media/box.jpg`), the numbered-ID line, and the Founding Litter scarcity line. The adoption counter remains hidden until real.
2. **Mid-page CTA.** The adoption section carries a second `WaitlistCTA` (source `adoption`, tracked separately end-to-end: analytics event, pixel, DB row). The one-button-style rule now covers three instances: hero, adoption, footer submit.
3. **Shipping timeline stays unpromised, but addressed.** New FAQ entry ("When do they hatch?") answers the question honestly with no date — a season promise we might miss costs more trust than no date. Revisit when a manufacturing schedule exists.
4. **Category phrase in body copy.** "desk companion for AI agents" now leads the "What does it actually do?" FAQ answer, satisfying §9.1's body-copy requirement.
5. **Follow-the-build link.** The footer renders a `follow the build` link only when `copy.footer.followBuild.url` is non-empty; it ships empty until the account exists (`../research/TODOs.md`).
6. **Placeholder polish.** The visible `placeholder · <note>` caption is removed from media stand-ins. The default drawn stand-in is now a desk-scale scene (blob small on a desk plane with contact shadow) instead of a full-frame portrait, so the hero reads as a physical object.
7. **Less blob repetition.** The S4 light strip is faceless — shell silhouettes lit from within, "Needs you" rendered largest/brightest with an amber label. Faces appear only in S2/S3, and the S2 pet beat now shows an actual drawn hand (`petting` on `BuddyBlob`).
