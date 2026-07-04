# 11 — Pass 2: Release Pipeline & Testing Truthfulness

The scaffolding from pass 1 (package.sh, release.yml, firmware-release.yml, flash page, manifest generator) is structurally right. This doc covers the places where the pipeline, followed end to end, produces something that doesn't work — plus the local testing trap.

## 1. (P0) `swift test` passes while running zero tests on Xcode-less Macs

Verified on this machine (CommandLineTools only, Swift 6.3.3): `swift test` prints "Build complete!" and **exits 0 without executing a single test**. The new `TestSupport/XCTestShim` makes the test target *compile* without Apple's XCTest, which is useful — but there is no runner, and nothing says so. `make test` is now a green light that means nothing locally. CI (macos-15, full Xcode) does run the real suite, so the safety net exists — but every local "tests pass" claim between pushes is false confidence, and this repo's agents run `make test` constantly.

**Fix, in order of preference:**

1. **Migrate the suites to Swift Testing** (`import Testing`, `@Test`/`#expect`). Swift Testing ships in the open-source toolchain and `swift test` runs it without Xcode — *verify on this machine first* (this CLT install showed no Testing module in the obvious lib paths; if a trivial `@Test` doesn't run here either, fall to option 2). The suites are assertion-style and mechanical to convert; the shim gets deleted.
2. **Make the false-green loud.** Teach the Makefile: `test:` checks for the real XCTest (same probe `Package.swift` uses) and, when absent, prints `WARNING: XCTest unavailable — tests COMPILED but DID NOT RUN. Use the HTTP e2e suite (make e2e) or CI for verification.` and **exits nonzero** unless `BUDDY_ALLOW_COMPILE_ONLY=1`. Also print the same warning from a `swift test` post-step if feasible. Cheap, immediate, honest.
3. Either way, update `CLAUDE.md`/`AGENTS.md` (they already carry the sandbox note) with the exact behavior so agents don't re-learn it.

Also worth adding to CI now that tests are real there: a step that fails if the executed-test count is suspiciously low (`swift test 2>&1 | tee`, grep "Executed N tests", assert N > 100) — insurance against the same class of silent-skip regression in CI itself.

## 2. (P0) Sparkle never makes it into a release artifact

The chain: `SparkleUpdateManager` loads `Contents/Frameworks/Sparkle.framework` at runtime → `package.sh` copies it only when `SPARKLE_FRAMEWORK_PATH` is set → `release.yml` sets it from `vars.SPARKLE_FRAMEWORK_PATH` — **but no workflow step ever downloads Sparkle onto the runner**, so the path can't exist on a fresh macos-15 machine. Additionally `Info.plist` ships `SUPublicEDKey = BUDDYGOTCHI_SPARKLE_PUBLIC_KEY_PLACEHOLDER`; if the framework ever did load, Sparkle would refuse (or worse, be misconfigured). Net: every release built by this pipeline has a permanently-dead "Check for updates".

**Fix:**

1. Add a workflow step before Package: download a pinned Sparkle release (`https://github.com/sparkle-project/Sparkle/releases/download/2.x.y/Sparkle-2.x.y.tar.xz`), verify its checksum, extract, and `export SPARKLE_FRAMEWORK_PATH=$PWD/Sparkle.framework`. Pin the version in one place (workflow env or a `SPARKLE_VERSION` file).
2. Generate the real EdDSA keypair (`generate_keys` from that same archive), put the public key in the `SPARKLE_PUBLIC_ED_KEY` secret (already plumbed to PlistBuddy), keep the private key in secrets for appcast signing.
3. `package.sh` signing of Sparkle: the current `find -type f -perm -111` walk misses proper bundle-level signing of the nested pieces. Sparkle 2 requires signing, in order: `Sparkle.framework/Versions/B/XPCServices/Installer.xpc` and `Downloader.xpc` (as bundles), `Versions/B/Autoupdate`, `Versions/B/Updater.app` (as a bundle), then the framework, then the app. Replace the walk with those explicit `codesign` calls; notarization will reject otherwise.
4. Consider dropping the ObjC-reflection loader once packaging is reliable: `SparkleUpdateManager`'s `unsafeBitCast` init dance is clever but brittle across Sparkle versions (also note: the `initWith…` returns +1; `takeUnretainedValue` over-retains — harmless leak of one controller, but it's the kind of code that breaks silently). The SPM product (`.package(url: sparkle-project/Sparkle)`) with `#if canImport(Sparkle)` is simpler and type-checked; the runtime-optional behavior for `swift run` can stay (Sparkle no-ops without a bundle). Keep the current approach only if avoiding the dependency is a deliberate choice — then add a comment saying so and a smoke assertion in the packaged-build checklist ("Check for updates opens the Sparkle window").
5. Appcast: generation is documented as a manual gate (fine) but not scripted. Add `app/tools/make-appcast.sh` wrapping `generate_appcast` against a downloads dir so the manual step is one command.

## 3. (P0) Released firmware always says it's 0.1.0

`platformio.ini` hardcodes `-DFW_VERSION=\"0.1.0\"`; `firmware-release.yml` builds `platformio run` with no version injection while `generate_release_manifests.py` stamps the *tag* version into the manifest. Consequence chain: device reports `0.1.0` in its status reply → app compares manifest `0.2.0 > 0.1.0` → "Update available" → user updates → device reboots, still reports `0.1.0` → **"Update available" forever**, and `FirmwareUpdater.recordDeviceVersion` will happily flip a fresh `.success` back to `.available`.

**Fix:** inject at build time. PlatformIO supports env-var expansion in build flags; the clean way:

```ini
build_flags =
    ...
    -DFW_VERSION=\"${sysenv.BUDDY_FW_VERSION}\"
```

with a default fallback via `extra_scripts` (a 5-line `pre:` script that sets `BUDDY_FW_VERSION=dev+<git-sha>` when unset), and in `firmware-release.yml`: `env: BUDDY_FW_VERSION: ${{ github.ref_name }}` (stripped of `fw-v`). Add a release-checklist assertion: after OTA, `buddyctl.py ping --json` reports `fw == manifest.version`. Also inject `GIT_SHA` the same way.

## 4. Version string hygiene

`release.yml` sets `BUDDY_VERSION: ${{ github.ref_name }}` — for tag `v0.3.1` that writes `CFBundleShortVersionString = v0.3.1`, and `AppMetadata.displayVersion` prepends another `v` → **"vv0.3.1"** in Settings; Sparkle version comparison against appcast entries also gets the stray prefix. Strip in package.sh (`VERSION="${VERSION#v}"`, one line, covers local + CI) — and keep `VERSION` (the file) as the dev default it already is. While there: `CFBundleVersion` gets `github.run_number` (good, monotonic); make the appcast's `sparkle:version` use the same build number.

## 5. Hosting doesn't exist yet (tracked, but now load-bearing)

Four shipped surfaces point at `buddygotchi.github.io`, which 404s today: `SUFeedURL` (…/releases/appcast.xml), the firmware manifest (Info.plist + `FirmwareReleaseService` default), `AppMetadata.supportURL` (…/help/), `AppMetadata.flashURL` (…/flash/). The app degrades politely (firmware check shows a failed state; help/flash links open a 404 in the browser — that one is *not* polite). Set up the Pages repo with the four paths — `docs/SUPPORT.md` → `/help/index.html` (or publish the markdown via Pages), `docs/flash/index.html` → `/flash/`, plus empty-but-valid `/firmware/` and `/releases/` — before any build reaches another human. Add a `docs/` deploy workflow (or host from this repo's Pages with a `gh-pages` branch) so SUPPORT.md edits publish automatically.

Flash-page specifics while touching it: the ESP Web Tools manifest sets `home_assistant_domain: "esphome"` — wrong product, triggers Home-Assistant affordances in the installer dialog; delete the key. And `new_install_prompt_erase: true` is right for recovery but the page copy should warn that installed GIF characters get wiped.

## 6. CI hardening (small, cumulative)

- `ci.yml` "Package app bundle" runs on every push/PR — good — but builds release *after* the debug test build without caching; add `actions/cache` on `.build` keyed by `Package.resolved` to keep CI under control as deps grow.
- Add the executed-test-count assertion (§1).
- Add `swift build -c release` diagnostics coverage — already implied by packaging; fine.
- `firmware-release.yml` builds on `ubuntu-latest` — fine for PlatformIO; add `pio check` (cppcheck) as a non-blocking step to start paying down firmware warnings.
- No workflow runs the copy-rules test for the *landing* page on app-repo changes — irrelevant; but consider one workflow-level `npm test` for `landing/` on landing changes if not already covered by Vercel builds (Vercel runs build, not tests).
- e2e: `app/tools/e2e/*.sh` now require the token (done) but nothing in CI can run them (needs a live app on a Mac runner with GUI-less constraints). Add a `make e2e` smoke to the *release checklist* doc rather than CI; and consider a headless variant: `swift run Buddygotchi` does run without a window server? (NSApplication under CI usually needs a UI session; macos runners have one — worth a spike: boot the app in background on the CI runner, run e2e-smoke.sh, kill it. If it works, the whole hook contract gets CI coverage.)

## 7. Release checklist (consolidate what exists into one doc)

`research/eng/TODOs.md` now holds per-release smoke items; PLAN.md holds another list; workflow summaries hold the appcast gate. Create `research/eng/RELEASE.md` as the single ordered checklist: tag → CI artifacts → clean-Mac Gatekeeper launch → hook smoke matrix (CLI + desktop app per agent) → approval allow/deny per agent → fail-open check → hardware pair/OTA/version-confirm → appcast PR → announce. Every item in it already exists somewhere; the consolidation is the deliverable. Delete the duplicates from TODOs.md/PLAN.md and link instead.

## Acceptance criteria

- On this Mac (no Xcode): `make test` either runs the suites (Swift Testing) or fails loudly with the compile-only warning; it can no longer exit 0 silently having run nothing.
- CI fails if fewer than ~100 tests execute.
- A tag build's `Buddygotchi.app` contains `Contents/Frameworks/Sparkle.framework` with valid nested signatures; Settings shows "v0.3.1 (N)" with a single `v`; "Check for updates" opens Sparkle's UI against the hosted appcast.
- `fw-v0.2.0` tag → device after OTA reports `0.2.0` via `buddyctl.py ping`; the app's firmware row says "Up to date".
- All four `buddygotchi.github.io` URLs resolve (help, flash, firmware manifest dir, releases dir).
- The ESP Web Tools dialog shows no Home Assistant prompt.
