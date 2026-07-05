# Boop — Landing Page

Waitlist / demand-test landing page for the Boop Founding Litter. Built to
`SPEC.md` in this directory. Independent of the rest of the repo — nothing here
imports from `../app` or `../src`.

## Stack

Next.js 15 (App Router, TypeScript) · Tailwind CSS v4 · Geist Sans · Neon Postgres
· Vercel Analytics. See `SPEC.md §3`.

## Local development

```sh
cd landing
npm install
cp .env.example .env.local     # fill DATABASE_URL, or: npx vercel env pull .env.local
npm run db:push                # apply db/schema.sql once (needs DATABASE_URL)
npm run dev                    # http://localhost:3000
```

The app boots with **no** env vars: without `DATABASE_URL` the waitlist API returns
503 and the page still renders (fail-open). To exercise the full flow locally
without a database, run with `ALLOW_INMEM=1` (an in-memory store — testing only).
Set `NEXT_PUBLIC_STRIPE_DEPOSIT_URL` only when the refundable $5 deposit Payment
Link is ready; when unset, `/welcome` omits that step. Point the Payment Link's
"after payment" redirect at `/held` and its webhook at `/api/stripe/webhook`
(event `checkout.session.completed`), then set `STRIPE_WEBHOOK_SECRET` so paid
deposits are recorded onto the signup row; when unset, the webhook no-ops and you
reconcile deposits by hand in the Stripe dashboard. Set `RESEND_API_KEY` to
send the first-signup confirmation email through Resend; when unset, signup still
works and email sending is skipped.

## Scripts

| Script | Purpose |
| --- | --- |
| `npm run dev` | Dev server |
| `npm run build` / `start` | Production build / serve |
| `npm run lint` | `next lint` |
| `npm run typecheck` | `tsc --noEmit` |
| `npm test` | Copy brand-law unit test (`tests/`) |
| `npm run test:e2e` | Playwright waitlist flow (`e2e/`) |
| `npm run db:push` | Apply `db/schema.sql` to `DATABASE_URL` |
| `npm run emails:build` | Embed canonical templates from `../emails/` |
| `npm run email:test -- you@example.com` | Send a rendered sample through Resend |

## Assets

No final photography/video exists yet. `public/media/` files are referenced by the
exact names in `SPEC.md §8.2`; until they exist, the `Media` component shows an
art-directed placeholder and swaps in the real file automatically when dropped in
(same filename, no code change). Agent logos are text wordmarks for now (`§8.3`).

## Deploying to Vercel

Import the repo, set **Root Directory = `landing`**, add a Neon
database from the Marketplace (injects `DATABASE_URL`), enable Analytics. Full
steps in `SPEC.md §11`. Add `RESEND_API_KEY` in Vercel when transactional email
is ready. `vercel.json`'s `ignoreCommand` skips deploys for pushes that don't
touch `landing/`.
