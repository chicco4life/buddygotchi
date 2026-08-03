# TODOs

Current open items that need a human action (accounts, assets, decisions).
Engineering release gates live in `eng/RELEASE.md`; verification commands live
in `eng/TESTING.md`.

## App and firmware release readiness

- [ ] **Finish app signing, notarization, and release automation decisions.** Use `eng/RELEASE.md` for the per-release gate and `eng/TESTING.md` for packaged-app smoke coverage.
- [ ] **Host firmware release files — deliberately withheld (2026-07-05).** Decision: don't publish firmware or expose flashing to end users yet. At release time, regenerate the artifacts into `landing/public/firmware/` with `cd firmware/esp32 && BUDDY_FW_VERSION=<ver> pio run -e m5stickc-plus && python3 tools/generate_release_manifests.py --version <ver> --base-url https://adoptaboop.com/firmware --build-dir .pio/build/m5stickc-plus --out-dir ../../landing/public/firmware` (or from the `fw-vX.Y.Z` workflow artifacts), and set `NEXT_PUBLIC_SHOW_FLASH=true` in Vercel to unhide `/flash/`. The flow was verified end-to-end locally on 2026-07-05 (manifests generated, flash page rendered the ESP Web Tools install button); once live, the Mac app's firmware updater will see the manifest.
- [ ] **Publish public appcast and support paths — /help and appcast ready; /flash hidden (2026-07-05).** `/help/` (`landing/src/app/help/`) and `/releases/appcast.xml` (valid empty Sparkle channel; release items come from `app/tools/make-appcast.sh`) go live with the next landing deploy — both are harmless pre-release. `/flash/` is built (`landing/src/app/flash/`, ESP Web Tools against `/firmware/esp-web-tools-manifest.json`) but returns 404 until `NEXT_PUBLIC_SHOW_FLASH=true` is set at build time, per the decision to keep flashing invisible to end users until hardware ships. Remaining: flip the flag and publish `/firmware/` at first firmware release.
- [ ] **Decide whether to enforce `swift-format` in CI** once the toolchain is pinned. Status 2026-07-05: still unpinned — CI runs whatever Swift ships on the `macos-15` runner (`ci.yml` only echoes `swift --version`). `make lint` already runs `swift-format lint` when installed. Recommended order: pin Xcode in `ci.yml` first (e.g. `xcode-select` a fixed version), then add the lint step; lint output drift across toolchains is the only real risk.

## Second hardware form factor — gaps found during the app restyle (2026-08-02)

The Mac app is now visually hardware-neutral (no device art, no board names, no
screen dimensions, and it no longer draws the creature). These are the
*functional* gaps that remain before a second board can ship alongside the M5.
All were deliberately out of scope for the restyle.

- [ ] **Discovery cannot tell the boards apart.** Both advertise `Buddy-XXXX`
  over the same Nordic UART service (`firmware/esp32/firmware/main.cpp:26-31`),
  and `BLEAckReply.StatusData` (`app/Boop/Outputs/ESP32/BLEManager.swift:20-30`)
  carries only `firmware` and `build`. Add a board id to the `status` reply
  before anything can branch on model.
- [ ] **One firmware manifest for all boards.** `FirmwareReleaseService.swift:36`
  points at a single `https://adoptaboop.com/firmware/manifest.json`, and
  `FirmwareUpdater` pushes whatever it downloads. With two boards in the field
  this ships an ESP32-S3 image to an ESP32-classic M5; the device's own
  `ota_begin` check is the only guard. This is the real correctness bug of the
  three — needs the board id above.
- [ ] **Wire budgets are tuned to the M5's 135x240 panel.** `Heartbeat.swift`
  truncates `msg` to 23 chars, `entries` to 6x48, and asserts 1536 bytes;
  `BLEManager.writeChunkSize` is 180; `HookServer.swift:346-353` caps request
  ids at 21 chars. A 280x456 landscape panel wants different numbers, and
  `RenderState` is the wire contract, so changing them is a firmware-coordinated
  change.

## Test isolation

- [ ] **Snapshot harness poisons a later test run.** Rendering snapshots writes
  `buddySpecies` into the shared `UserDefaults` domain (SettingsView's
  `@AppStorage`), and `renderState` reads `UserDefaults` before engine state
  (`Heartbeat.swift:47`). The next `swift run BoopTests` then fails
  `EngineIntegrationTests.testSetSpeciesUpdatesStateAndHeartbeat` with "blob is
  not equal to duck" until `defaults delete BoopTests buddySpecies`. Pre-existing;
  fix by having the tests use a scratch defaults suite.

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
