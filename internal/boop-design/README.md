# Boop animation and mood design package

Updated 2026-09-28. The code-based animation/SFX bank and approved mood-graph
handover, published together for review and later integration. Nothing here
changes the shipped app, firmware enums, steering or hardware assets.

- [Animation bank](boop-sound-bank-v4/README.md): editable SVG generators,
  procedural sounds, portable browser player and coverage index.
- [Offline review](boop-sound-bank-v4/review/boop-moods.html): download/open
  the HTML in a browser, or serve the review directory locally.
- [Mood graph and JEV handover](boop-mood-spectrum-v2/HANDOVER.md):
  neighbor choices, dramatic-edge gating, migration and voice guidance.
- [Machine-readable graph](boop-mood-spectrum-v2/mood-graph.json).

From the **repository root**, with Node.js:

```sh
node internal/boop-design/boop-mood-spectrum-v2/validate.mjs
node internal/boop-design/boop-sound-bank-v4/source/build.mjs
node internal/boop-design/boop-sound-bank-v4/qa/check.mjs
```

The generated player and offline review are checked in for immediate use.
The larger per-scene manifest and expanded SVG copies are reproducible and
ignored, rather than duplicating the compact source in Git. Use the builder's
`--svg` option to write **every** SVG selection to
`boop-sound-bank-v4/dist/svg/`. Each selection's procedural sound score and
new-scene voice window are in the generated `boop-sound-bank-v4/manifest.json`.

Browser QA is optional and needs Playwright, pngjs and Chromium:

```sh
npm --prefix internal/boop-design install --no-save --package-lock=false playwright pngjs
cd internal/boop-design
npx playwright install chromium
cd ../..
node internal/boop-design/boop-sound-bank-v4/qa/browser.mjs
```

Alternatively point BOOP_PLAYWRIGHT_MODULE and BOOP_PNGJS_MODULE at existing
module files, and BOOP_QA_BROWSER at an installed Chromium executable.
These dependencies are QA-only; building and playing the bank needs none of
them. The checks do not launch Boop, touch Bluetooth, call JEV, use ElevenLabs
or consume credits. Each script supports `--help`.

The imported bank is self-contained: no absolute workstation paths and no
dependency on the design workspace's V3 folder. Independent V3 fingerprints
check preservation of the older SVGs and scores. See the
[verification evidence](../../plan/evidence/2026-09-28-mood-design-push/README.md).

## Integration boundary

Keep this review package separate from `internal/tools/facegen/design/` and
`internal/tools/sfxgen/pack/` until the production transition is deliberately
implemented and tested. That work needs matching updates to mood persistence,
JEV choices, event-to-state mapping, protocol/firmware names, face and sound
generation, and the specifications. The generic harness must not acquire mood
graph logic. Publication of this package is not visual approval or a claim of
device support.

No recordings, execution logs, credentials, enclosure CAD, or the sound chat's
unfinished scripts are part of this publication.
