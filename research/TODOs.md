# TODOs

Current open items that need a human action (accounts, assets, decisions).
Engineering TODOs live in `eng/TODOs.md`.

## Landing page — links and accounts to create

- [ ] **Build-in-public account (X/Twitter).** Create the account (MARKETING.md §4.11 step 1), then set `copy.footer.followBuild.url` in `landing/src/lib/copy.ts` — the footer "follow the build" link renders only once that string is non-empty.
- [ ] **Verify `hello@buddygotchi.com` works** (or update `copy.footer.contactEmail`) before any traffic — it's the footer contact link.
- [ ] **Domain + brand-defensive Google campaign** on "buddygotchi" once the domain is live (MARKETING.md §4.5).

## Landing page — assets

- [ ] **`landing/public/media/hero.jpg`** — generated mock of the money shot (blob on desk, amber glow, hand mid-pet); replaced by real film when the product exists. Spec in `landing/public/media/README.md`.
- [ ] **`landing/public/media/box.jpg`** — generated mock of the open adoption box (numbered tag, cream cable; no care card).
- [ ] **Real `og.jpg` (1200×630)** for social cards, replacing `landing/public/og.svg`; update the reference in `landing/src/app/layout.tsx`.

## Landing page — decisions to revisit

- [ ] **Shipping window.** The FAQ deliberately promises no date ("When do they hatch?"). Once a manufacturing schedule is confident, tighten that answer — a real window converts better than none, but only if we can hit it.
- [ ] **Adoption counter.** Stays hidden (`NEXT_PUBLIC_SHOW_COUNTER` unset) until there are real signups worth showing.
- [ ] **$5 refundable deposit step** on /welcome (MARKETING.md §2.4) — deferred until email capture is proven; needs Stripe.
