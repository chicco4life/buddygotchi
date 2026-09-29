# Boop animation and mood design package

Updated 2026-09-29. The code-based animation/SFX bank and approved mood-graph
handover. The bank is the one source of the device's designs and sounds:
`facegen` runs its generator for the faces and `sfxgen` imports its
timelines and synthesiser ([plan/DEVICE.md](../../plan/DEVICE.md) §6,
[plan/VOICE.md](../../plan/VOICE.md) §10), so a change here changes the
firmware once they're rerun.

- [Animation bank](boop-sound-bank-v4/README.md): editable SVG generators,
  procedural sounds, portable browser player and coverage index.
- [Offline review](boop-sound-bank-v4/review/boop-moods.html): download/open
  the HTML in a browser, or serve the review directory locally.
- [Mood graph and JEV handover](boop-mood-spectrum-v2/HANDOVER.md):
  neighbor choices, dramatic-edge gating, migration and voice guidance.
- [Machine-readable graph](boop-mood-spectrum-v2/mood-graph.json). The
  app ships it as `app/BoopKit/Actions/MoodGraph.swift`, which a test
  holds to this file move for move ([plan/harness/DECISIONS.md](../../plan/harness/DECISIONS.md) §4).
- [Voice asset bank and agent selection guide](assets/boop-voice-v1/README.md):
  40 recorded Robot Minion takes, three local DSP alternatives, original masters,
  dictionary, lookup indexes and a tested host-side selector.

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

## How the device uses it

`make -C internal faces` runs the bank's generator
(`internal/tools/facegen/bank.mjs` calls `makeScene` for every design) into
`internal/tools/facegen/build/`, which git ignores, and turns the SVGs into
`firmware/assets/faces.h`; `node internal/tools/sfxgen/sfxgen.mjs` then bakes
the timelines, in the voice-first mix, into `firmware/assets/sfx.h`. Nothing
is copied out of the bank by hand. The older moods' designs must come out as
`qa/v3-fingerprints.json` has them; change one only deliberately, with the
fingerprints in the same commit. The generator tags each flip-book step's
face and mouth (`data-part`) and its blink (`data-blink`), which facegen and
the device use; `qa/check.mjs` must pass after any change.

The mood graph belongs to the Mac's Mood action, never the generic harness.
Integration is not visual approval: the owner approves the new art and
sounds before they merge to main.

The original animation publication contained no recordings. The separately
authorized voice asset folder now contains only the selected voice bank and its
integration guide. No execution logs, credentials, account ledgers, enclosure CAD,
other voices or unused recording intermediates are included.
