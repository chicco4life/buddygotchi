# UI/UX pass, both surfaces — 2026-09-11

A polish pass over the Mac app and the device, on a shared palette. Owner chose
"Boop Cream" (warm paper, terracotta accent) and the black-field/cream-ink
treatment for the device.

## The palette

One palette, inverted field. The app is cream paper with warm ink
(`app/Boop/Theme/BuddyTheme.swift`); the device keeps the ink and puts it on
black (`firmware/esp32/firmware/palette.h`).

The device field is black rather than cream on purpose. Black is free on AMOLED —
the pixels are off — and a cream field would light all 456×280 of them, cost
battery, glow in a dark room, and burn in under a persistent dashboard. Pure
white ink on black is harsh at night, so the ink is a warm cream `(255,219,173)`
that reads as lamp light and matches the app's paper.

Three semantic tones mean the same thing on both screens: **amber = needs you,
sage = done, rose = affection**. Terracotta marks every primary action in the
app; amber never does. `PaletteTests` fails the build if that erodes.

## Mac app

- Sections are a small tracked-out label above a card, not rules between blocks.
- Status opens with a tone dot that breathes only while work is live.
- Session rows carry their tone in a 3 pt leading bar and a per-agent glyph.
- Progress is three stat tiles over the twelve-week grid; cells are 15 pt squares
  on the sage scale, empty days are a warm well, today carries a terracotta ring,
  and a less/more legend sits on the caption line.
- Battery is a small drawn pip, amber under 25%, matching the device's own mark.
- Settings and setup moved off the system's cold greys onto the same paper.
- Setup's four copies of a 42 pt glyph floating in an empty 260×200 frame became
  one composed `OnboardingArt` slot. No face appears in setup — `UX-APP.md` is
  explicit that the physical device owns Buddy's expression.

Layout bug found and fixed: the leading accent bar was an `HStack` sibling. A
bare `Shape` has no ideal height, so it made the needs-you card flexible and the
popover stretched it to fill the column. The bar is now an overlay.

## Device

- **Arms.** New, and a deliberate amendment to §7's "a face, not a body": the
  owner asked for "a small/tiny body — or maybe just arms? — that can point and
  wave". There is still no torso, no legs and nothing joining them. An arm
  follows the brow's rule — it exists only while it is doing something — so at
  rest the face is still two eyes and a mouth on black. Three moments only:
  the hello wave, the celebration, and the dashboard gesture. Never over a card.
- **Animation audit.** The heart is one shape, better proportioned, and now
  capped at one every 2.5 s ("there are too many hearts"): a further boop still
  squishes and smiles but grants no heart, so petting reads as an affectionate
  beat rather than a stream. Confetti went from six hard dots to five smaller
  ones that fade out instead of blinking off together.
- **Boop, revised after review** (owner: "has too much going on… if the heart is
  in the middle it looks like a weird pimple"). The blush is gone from the boop,
  leaving squish + smile + one heart. The heart no longer rises from the gap
  between the eyes — it rises **diagonally off the left side of the face**,
  starting beside the cheek clear of the eye and drifting out and up. Centred,
  it sat *on* the face like a blemish; off to the side it reads as emitted.
  Left specifically, because the greeting wave is the right arm and level‑3
  greet grants a heart at the same time: same side they collide, opposite sides
  the pose is balanced (see `device-greet-wave.png`). Greet and the celebration
  keep their blush; only the boop lost it.
- **Proportions.** The dashboard board takes precedence, but the buddy shrinks
  to 42%, not 28% — at 28% it stopped reading as a creature. The table is now
  centred in the band below the buddy rather than pinned to a fixed top, which
  had left ~80 px of dead screen at one or two agents. One hairline under the
  column heads; zeros dimmed rather than dropped.
- **Card footer.** A hairline across the top (still no box — 8-bit fills read as
  mud), tool and gloss sharing the left edge, gloss stepped down to the soft ink.

### Device bug found and fixed

The needs-you and uh-oh field washes were rendering the **identical colour**,
`(36,0,0)`. `animMix` blends in RGB565 and the 8-bit canvas then *truncates* to
RGB332 (`R5>>2`, `G6>>3`, `B5>>3`), so a blend quantizes far more coarsely than
the endpoint lattice suggests and loses hue as it darkens. Both washes were
re-chosen against the real path: needs-you now rests at `(72,36,0)` amber and
peaks at `(109,72,0)` on the second nudge rung; uh-oh sits at `(72,0,0)` rising
to `(109,0,0)`. They differ by hue, at matched brightness. See the two wash
images below.

## Verification

- `make test`: **349 passed, zero skipped** (was 345 before four new
  `PaletteTests`), using the repository Swift XCTest shim, including offscreen
  native-view rendering in both appearances and both languages.
- `make build`: Boop and BoopSignal built.
- `tools/pio_ws.sh run -e ws-amoled164`: built, flashed to hardware.
- **43/43 device goldens re-recorded and verified at 0.000000 error** on
  shipping firmware (`ws-amoled164`), including five new dashboard cells and two
  heart cells added to `tools/shot_cells.py`.

  **Correction.** An earlier run in this session reported "43/43 at 0.000000"
  and that result was not trustworthy. `golden.py record` copies whatever is in
  `/tmp/boop-shots`, and the `golden.py check` that followed compared *the same*
  `/tmp` images against goldens recorded from them — a circular check that
  validates nothing about whether the captures are current. Six goldens (the
  three card states, both uh-oh states and `perch-needsYou`) had in fact been
  baked from pre-wash-fix renders, because `shots.py` had silently aborted:
  its `require_exclusive()` guard refuses while `state.connected` is true, and
  `dataConnected()` stays true for 60 s after *any* frame — including the USB
  frames `shots.py` itself had just sent. With its output redirected to
  `/dev/null` that abort was invisible.

  The final result above was produced properly: `rm -rf /tmp/boop-shots`, a full
  capture, `record`, then a **second independent capture** taken after the 60 s
  liveness window expired, and only then `check`. That is a real round-trip.
  Filed as a breadcrumb against `tools/golden.py`.
- Offscreen app screenshots reviewed for Overview, needs-you, Settings and all
  five setup steps, light and dark.

### Not verified

- **Webcam verification of animation smoothness is still outstanding.** It was
  attempted twice. The first attempt failed before recording with
  `Camera permission timed out`. After the owner granted camera access, a 3 s
  framing clip confirmed Buddy was in shot, and one 7 s greet-wave clip was
  recorded — but the footage was not usable for judging motion: the camera
  auto-exposed for a bright room and crushed the screen to near-black, the
  device sat small and oblique in frame with a specular reflection over its
  right half, and the panel was at the dimmed 90/255 level rather than 210.
  The session ended before re-framing. All room footage was deleted from `/tmp`
  and none entered Git.

  To retry: place Buddy larger and face-on to the lens, avoid a bright
  background behind it, and keep the panel awake (a state change or button
  press stamps `lastInput`; it drops to 90/255 after two minutes idle, and a
  card raises it to 255). Then record greet-wave, done-dance and boop, which
  are the three animations this change touched.

  The device evidence here is therefore frozen-clock USB screenshots, not
  motion review. **Screenshots cannot certify smoothness**; the arm motion,
  heart cooldown and confetti fade are verified as geometry and timing in code
  and goldens, not as observed motion on hardware.
- BLE integration with the Mac app, live-model and native-editor flows.

## M5StickC Plus 2 retired

While running the documented build checks I found `pio run -e m5stickc-plus`
failing `checkprogsize`: the image was 1,739,865 bytes against a 1,572,864-byte
app slot, **167 KB over**. Pre-existing — HEAD (ee6db76) is already at 110.5%,
and this work adds ~2 KB — so not a regression. `lgfx_efont_kr_16`, the Korean
font, is 324,224 bytes of it, ~19% of the image and twice the overage.

I first fixed it by reclaiming the 896 KB `spiffs` partition, which no firmware
code ever mounted (the only `esp_partition` use is OTA bookkeeping in
`guard.h`), giving two 1.9 MB OTA slots and an 85.6% image with no code change.

The owner then retired the board outright: "the old device I no longer use and
we don't need to support". So the partition fix is moot and the M5 is gone:

| Removed | |
| --- | --- |
| `[env:m5stickc-plus]`, `[env:m5stickc-plus-debug]` | build targets; `default_envs` is now `ws-amoled164` |
| `partitions.csv` | the 4 MB table (only the 16 MB one remains) |
| `firmware/hal/hal_m5stick.cpp` | the M5 HAL |
| `M5StickCPlus2` / M5GFX | dependency |
| `BOARD_WS_AMOLED_164` conditionals | one board needs no board switch |
| `HAL_LANDSCAPE`, `HAL_UI_SCALE`, `HAL_HUD_H` | portrait-only layout constants; the latter two were already unreferenced |
| 14 portrait ternaries in `main.cpp` / `face.h` | dead branches for the 135x240 screen |

The collapsed ternaries are behaviour-preserving, and the Waveshare image is
byte-identical before and after at 1,236,507 bytes. `archived/firmware/esp32/`
still contains the full M5 generation and was deliberately left untouched.

One thing deliberately **not** changed: `BuddyOutputTarget.hardware` keeps its
legacy `"m5stack"` raw value in `app/Boop/Views/Onboarding/OnboardingModel.swift`.
It is persisted in user defaults, so renaming it would silently reset existing
users' output choice. Its comment already says so.

## Images

| File | What |
| --- | --- |
| `app-overview-light.png` | Overview, working, light |
| `app-needs-you-dark.png` | Needs you with a card, dark |
| `app-settings-light.png` | Settings on cream |
| `app-setup-agents.png` | Setup, agents step |
| `device-dashboard.png` | Board with three agents, buddy gesturing |
| `device-dashboard-one-agent.png` | One agent — table centred, not riding the top |
| `device-cheer-arms.png` | Both arms raised, five fading confetti dots |
| `device-greet-wave.png` | One arm waving |
| `device-heart.png` | The single heart at its peak |
| `device-needs-you-wash.png` | Amber wash `(72,36,0)` |
| `device-uhoh-wash.png` | Red wash `(72,0,0)` — compare with the above |
| `device-card-footer.png` | Card footer: hairline, aligned tool and gloss |
