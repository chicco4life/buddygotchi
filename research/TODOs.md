# TODOs

Current open items that need a human action (accounts, assets, decisions).
Engineering release gates live in `eng/RELEASE.md`; verification commands live
in `eng/TESTING.md`.

## App and firmware release readiness

- [ ] **Finish app signing, notarization, and release automation decisions.** Use `eng/RELEASE.md` for the per-release gate and `eng/TESTING.md` for packaged-app smoke coverage.
- [ ] **Host firmware release files — deliberately withheld (2026-07-05).** Decision: don't publish firmware or expose flashing to end users yet. At release time, regenerate the artifacts into `landing/public/firmware/` with `cd firmware/esp32 && BUDDY_FW_VERSION=<ver> pio run -e m5stickc-plus && python3 tools/generate_release_manifests.py --version <ver> --base-url https://adoptaboop.com/firmware --build-dir .pio/build/m5stickc-plus --out-dir ../../landing/public/firmware` (or from the `fw-vX.Y.Z` workflow artifacts), and set `NEXT_PUBLIC_SHOW_FLASH=true` in Vercel to unhide `/flash/`. The flow was verified end-to-end locally on 2026-07-05 (manifests generated, flash page rendered the ESP Web Tools install button); once live, the Mac app's firmware updater will see the manifest.
- [ ] **Publish public appcast and support paths — /help and appcast ready; /flash hidden (2026-07-05).** `/help/` (`landing/src/app/help/`) and `/releases/appcast.xml` (valid empty Sparkle channel; release items come from `app/tools/make-appcast.sh`) go live with the next landing deploy — both are harmless pre-release. `/flash/` is built (`landing/src/app/flash/`, ESP Web Tools against `/firmware/esp-web-tools-manifest.json`) but returns 404 until `NEXT_PUBLIC_SHOW_FLASH=true` is set at build time, per the decision to keep flashing invisible to end users until hardware ships. Remaining: flip the flag and publish `/firmware/` at first firmware release.
- [ ] **Decide whether to enforce `swift-format` in CI** once the toolchain is pinned. Status 2026-07-05: still unpinned — CI runs whatever Swift ships on the `macos-15` runner (`ci.yml` only echoes `swift --version`). `make lint` already runs `swift-format lint` when installed. Recommended order: pin Xcode in `ci.yml` first (e.g. `xcode-select` a fixed version), then add the lint step; lint output drift across toolchains is the only real risk.

## Landing page — links and accounts to create

- [ ] **Build-in-public account (X/Twitter).** Create the account (MARKETING.md §4.11 step 1), then set `copy.footer.followBuild.url` in `landing/src/lib/copy.ts` — the footer "follow the build" link renders only once that string is non-empty.

## Landing page — assets

- [ ] **`landing/public/media/hero.jpg`** — generated mock of the money shot (blob on desk, amber glow, hand mid-pet); replaced by real film when the product exists. Spec in `landing/public/media/README.md`.
- [ ] **`landing/public/media/box.jpg`** — generated mock of the open adoption box (numbered tag, cream cable; no care card).
- [ ] **Real `og.jpg` (1200×630)** for social cards, replacing `landing/public/og.svg`; update the reference in `landing/src/app/layout.tsx`.

## Landing page — decisions to revisit

- [ ] **Shipping window.** The FAQ deliberately promises no date ("When do they hatch?"). Once a manufacturing schedule is confident, tighten that answer — a real window converts better than none, but only if we can hit it.
- [ ] **Adoption counter.** Stays hidden (`NEXT_PUBLIC_SHOW_COUNTER` unset) until there are real signups worth showing.
- [ ] **Paid ad campaign + conversion pixels.** The ad-pixel code (Reddit/X/Meta env-gated pixels, `Pixels.tsx` + `lib/pixels.ts`, fired from `lib/submit.ts`) was removed 2026-07-05 — deferred until a paid campaign is actually planned. When it is: recover that code from git history (design recorded in `landing/SPEC.md` §7.3), create the ad accounts ~a week early so pixels accumulate history before spend, and set the `NEXT_PUBLIC_*_PIXEL_ID` vars in Vercel.
- [ ] **Read the price-expectation answers** (Van Westendorp-lite, MARKETING.md §3.3) once ~100 exist: `select price_expectation, count(*) from signups where price_expectation is not null group by 1` — locates the price better than the cohort test alone.
