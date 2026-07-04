# TODOs

Current open items that need a human action (accounts, assets, decisions).
Engineering release gates live in `eng/RELEASE.md`; verification commands live
in `eng/TESTING.md`.

## App and firmware release readiness

- [ ] **Finish app signing, notarization, and release automation decisions.** Use `eng/RELEASE.md` for the per-release gate and `eng/TESTING.md` for packaged-app smoke coverage.
- [ ] **Host firmware release files.** Publish the firmware `manifest.json`, ESP Web Tools manifest, and versioned `.bin` files before OTA or web-flasher release checks can pass.
- [ ] **Publish public appcast and support paths.** Keep `/releases/appcast.xml`, `/firmware/`, `/flash/`, and `/help/` live for release builds.
- [ ] **Decide whether to enforce `swift-format` in CI** once the toolchain is pinned.

## Landing page — links and accounts to create

- [ ] **Build-in-public account (X/Twitter).** Create the account (MARKETING.md §4.11 step 1), then set `copy.footer.followBuild.url` in `landing/src/lib/copy.ts` — the footer "follow the build" link renders only once that string is non-empty.
- [ ] **Verify `hello@adoptaboop.com` works** (or update `copy.footer.contactEmail`) before any traffic — it's the footer contact link.
- [ ] **Brand-defensive Google campaign** on the lockups — "boop pet," "boop desk pet," "boop computer," "adopt a boop" — now that adoptaboop.com is live; never bid on bare "boop" (MARKETING.md §1.5, §4.5).
- [ ] **Enable Vercel Web Analytics** on the landing project (dashboard → Analytics). The code is already instrumented (`cta_click`/`modal_open` with price cohort, `signup` with cohort, `deposit_click`, `price_expectation`, `copy_referral`, scroll depth) — nothing shows up until it's switched on. Revisit deeper funnel tooling (e.g. PostHog) only if the Vercel event views prove too coarse during the test.
- [ ] **Resend account for the waitlist email.** Create account, add adoptaboop.com as a verified domain (SPF + DKIM DNS records), then build the one-paragraph in-universe confirmation email (from "The Litter": adoption position, referral link, honest expectations — MARKETING.md §3.6). Sending code doesn't exist yet; add it to the `/api/waitlist` submit path once the domain verifies.
- [ ] **Stripe account + $5 deposit Payment Link.** Sole proprietor is fine to start (no incorporation needed). Create a $5 "hold your adoption number" Payment Link (fully refundable — write the refund promise into the link's description), then set `NEXT_PUBLIC_STRIPE_DEPOSIT_URL` in Vercel env. The /welcome deposit block renders automatically once it's set, passing the signup's referral code as `client_reference_id`. Form an LLC before charging for actual hardware (deposits-as-liabilities are fine as an individual; product revenue + hardware liability is when the entity matters).
- [ ] **Ad pixel IDs** (`NEXT_PUBLIC_REDDIT_PIXEL_ID` etc., see `landing/.env.example`) when the paid smoke test starts — create the Reddit/X/Meta ad accounts a week early so the pixels accumulate history before spend.

## Landing page — assets

- [ ] **`landing/public/media/hero.jpg`** — generated mock of the money shot (blob on desk, amber glow, hand mid-pet); replaced by real film when the product exists. Spec in `landing/public/media/README.md`.
- [ ] **`landing/public/media/box.jpg`** — generated mock of the open adoption box (numbered tag, cream cable; no care card).
- [ ] **Real `og.jpg` (1200×630)** for social cards, replacing `landing/public/og.svg`; update the reference in `landing/src/app/layout.tsx`.

## Landing page — decisions to revisit

- [ ] **Shipping window.** The FAQ deliberately promises no date ("When do they hatch?"). Once a manufacturing schedule is confident, tighten that answer — a real window converts better than none, but only if we can hit it.
- [ ] **Adoption counter.** Stays hidden (`NEXT_PUBLIC_SHOW_COUNTER` unset) until there are real signups worth showing.
- [x] **$5 refundable deposit step** on /welcome (MARKETING.md §2.4) — page side implemented (env-gated `WelcomeDeposit`); goes live when the Stripe Payment Link exists and `NEXT_PUBLIC_STRIPE_DEPOSIT_URL` is set (see accounts section above).
- [ ] **Read the price-expectation answers** (Van Westendorp-lite, MARKETING.md §3.3) once ~100 exist: `select price_expectation, count(*) from signups where price_expectation is not null group by 1` — locates the price better than the cohort test alone.
