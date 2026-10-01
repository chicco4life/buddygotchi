# Slime export validation

Updated 2026-10-02. Package-only checks; no production/hook/firmware/device
integration is claimed. Historical face audition QA is recorded separately
in [contracts/historical-face-qa.json](contracts/historical-face-qa.json).

From the repository root, Node 18+:

```sh
node internal/boop-design/slime-blob/tools/build.cjs
node internal/boop-design/slime-blob/tools/check.cjs
```

The offline check covers retained IDs, all mood/state/edge checklist
entries, ordinary-graph connectivity, canonical catalogue export, seven
accepted motion hashes, unchanged blue gel material, deterministic finite
bounded procedural sound output/mute, and local Markdown links.

Optional real-browser QA requires Playwright and Chromium. Use existing
dependencies through `BOOP_PLAYWRIGHT_MODULE` (path to the Playwright module)
and `BOOP_QA_BROWSER` (Chromium executable). Otherwise it resolves the
installed `playwright` package and its managed Chromium. These are test-only
dependencies, not required by the preview, builder or offline validator.

With the review server running from the README, from the repo root:

```sh
node internal/boop-design/slime-blob/tools/browser.cjs
```

`BOOP_QA_URL` overrides the local URL; defaults to http://127.0.0.1:4190/.
`BOOP_QA_OUTPUT` chooses a screenshot output directory; by default a fresh
temporary directory is used. `BOOP_CAPTURE_FACES=0` skips per-face screenshots,
not the expression-selection checks. `--help` is supported by all package
scripts. QA images are review evidence, not packaged runtime assets.

## This export's actual result

Passed on 2026-10-02:

- Deterministic builder and offline validator: 42 moods, 44 expressions,
  22 states, 924 explicit coverage cells; 295 directed edges (224 ordinary,
  71 dramatic), ordinary graph strongly connected and retained IDs intact.
- All seven accepted V1 source hashes and the original blue gel fragment
  shader hash match; catalogue export and local Markdown links pass.
- 27 seeded procedural sound renders (nine recipes × three variants)
  are deterministic/finite/bounded; mute is silent. Peak at the default
  audition gain was 0.28533. This is numeric QA, not physical listening QA.
- Real headless Chrome: shader compilation, all expression selections and
  normalized weights, three happy gestures, mouse/touch drag, bounded
  pull, release settling, mobile width, reduced-motion path, manual sound
  button/play/stop UI, and a separate genuinely WebGL-disabled Canvas
  fallback all passed. No browser console/page errors remained.
- Every package script's `--help` ran; Git whitespace checks and the
  repository's identical CLAUDE.md/AGENTS.md check passed.

The browser run used installed Playwright/Chrome overrides and
`BOOP_CAPTURE_FACES=0`: all faces were selected/checked, but this export
did not generate a new full contact sheet or individually replay every
gesture. Temporary drag/mobile/fallback screenshots were inspected locally
and are not committed. No runtime assets depend on those pictures.

## Limits that remain

- V3 artwork and the new SFX sketches need owner artistic/listening review.
- There is no implemented activity router/props, production graph gating,
  complete mood×state animation matrix or synchronized audio cue backend.
- All expressions are browser-selectable. Prior recipe execution checked
  three happy gestures; it did not exhaustively play every recipe.
- Drag checks concern browser-local releases. Cross-container termination,
  real touch hardware and physical audio latency are separate tests.
- WebGL and Canvas do not have identical materials. Neither is validated
  on ESP32; no firmware build/flash, hooks doctor, Jev eval or paid API call
  is needed or performed for this isolated design export.
