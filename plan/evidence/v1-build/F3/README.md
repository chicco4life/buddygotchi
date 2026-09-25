# F3: Device behaviour — evidence

Run 2026-09-26 on branch `v1-overnight`. Device checks ran against firmware
`a05f38af45`, flashed from that commit. The spec and preset commits after
it don't change the firmware. Outputs: [perf.json](perf.json) and
[soak.json](soak.json).

## What was built

- **Behaviour state machine** (`firmware/src/app/behaviour.*`, pure C++).
  It holds what the Mac said, the moment, idle life, the needs-you ladder,
  local reactions to input, and the light, backlight and sound cues. Every
  time-based change (a moment ends, a rung, an idle-life event, the no-app
  timeout, threads closing) happens at its exact millisecond, so a frozen
  clock gives the same frames on the board and in the simulator. The device
  core (`app/device.*`) now only parses, recognises gestures and draws.
- **Base states:** idle, working (busier glances with 3 or more sessions
  busy), asleep (slow breathing, no blinks), and no app (slow blinks only).
  Night makes Boop drowsier and dims the backlight. Hunger rumbles and
  peeks hopefully, and starving adds heavy lids and an empty bowl.
- **Idle life:** blinks, glances, peeks and a little bob every 2–6 s,
  slower when tired, hungry or at night. The random choices come from the
  device's seeded generator, so they repeat exactly.
- **Needs you:** rung 1 (lean in, amber, `chirp`), rung 2 at 45 s (leans
  further, `chirp`), rung 3 at 2 min (three 200 ms amber pulses, `pulse`).
  Focus makes it visual only. A tap nods, hushes the nudges and freezes the
  lean. When `attn` leaves the `state`, the device nods.
- **Moments:** the pace from `mood` speeds them up or slows them down, and
  energy makes a cheer a size smaller or bigger. Big cheers turn on a warm
  light and cue a `jingle`. The mouth follows a mumble's syllables, and
  mumbles are dropped in quiet, focus and needs you. **Attention wins:**
  while something needs you, only `nod`, `listening`, `thinking`, `shrug`
  and `zip` play.
- **Gestures:** pressing BOOT or the face squashes the face at once, and a
  finger on the strip lights its top line. A tap on the face or BOOT gives a
  wiggle, or a nod during needs you, and sends `tap`. Holding BOOT shows
  `listening`, then `thinking` on release, then a `shrug` after 8 s if
  nothing replies (`talk_on` and `talk_off`). Touch and hold on the face
  shows a mood face and sends `feel`, which is new. Touch and hold on the
  strip toggles focus and sends `focus`. A tap on the strip cycles the
  screens, a tap on threads or stats goes back to the face, and both
  screens close after 10 s.
- **dbg.state** gained `hushed`, `life`, `night`, `hungry` and `sfx`, and
  `audio.playing` now follows the mouth.
- **boopctl:** `soak --minutes N`, which sends random realistic traffic and
  inputs, plus one 35 s silence. New webcam presets: `ladder`, `cheers` and
  `tap`.

## Checks

| Check | Result |
| --- | --- |
| L0 `make fw-test` | Passed: 55 tests, 17 of them new behaviour tests. They cover the ladder to the millisecond (rungs, chirps, pulse on/off times), focus, the tap hush, the nod on clearing, attention winning, moment ends and replacement, pace and energy, mumbles with mouth sync and the quiet and focus rules, idle-life gaps of 2–6 s, asleep breathing, no app at 30 s with dimming and a reconnect blink, night backlight, threads closing at 10 s, push-to-talk ending in a shrug, the mood faces, press feedback within 20 ms, hunger never lighting or sounding, and gestures through the device core |
| L1 goldens | Passed: 10 scenarios (2 new: `behaviour`, `life`), 0 expect failures. **22 new pictures and 8 changed ones were reviewed** (below) |
| L2 scenarios | Passed: `boopctl run` on all 10 scenarios. Every expect passed on the board, and all 80 screenshots were **identical** to the simulator's |
| L2 ping | SHA `a05f38af45` matches the commit under test; link `none` (not `ble`); 159 KB free |
| L2 perf | Passed: `perf --seconds 30 --motion` gave a minimum of **45 fps** (mean 58), minimum heap 157.5 KB, and no reset |
| Soak | Passed: `soak --minutes 20` sent random states, moments and inputs, with one 35 s silence. **No reset** in 219 samples, minimum heap 157,336 bytes from the first minute to the end (**0 drift**), and the device still answering. Calm snapshots brought back the plain face with no moment stuck ([soak.json](soak.json)) |
| L3 framing | Passed (screen found; USB-C to the right) |
| L3 clips | Reviewed: [ladder](webcam-ladder.png) (the needs-you screen with a sped-up clock through rungs 2 and 3, then the tap's nod and back to leaning in; the RGB LED is on the board's back, out of view, so the pulses are checked by L0 and `led` in `dbg.state`), [cheers](webcam-cheers.png) (sizes 1–3 with the warm glow deeper at 2 and 3, returning to working each time; the doubled eyes at 4.5 s are camera blur during a blend), and [tap](webcam-tap.png) (three wiggles with a happy squint, from BOOT, the face and BOOT again). The colours and text read correctly, with no tearing or stuck frames |

Pictures: [sim-behaviour.png](sim-behaviour.png) (8 of the new goldens) and
[sim-needs-you-tapped.png](sim-needs-you-tapped.png).

## Goldens accepted (after looking)

- **Changed on purpose:** `base/asleep` (breathing), `base/reconnect` (the
  reconnect blink), `inputs/face` (the injected hold now plays listening
  and then thinking), `needs_you/cleared` (the nod on clearing), and the
  four `mumble` pictures (the mouth is open mid-syllable).
- **New in `behaviour`:** press feedback (a slight squash at 16 ms), the
  tap wiggle, listening, thinking, the too-slow shrug, feel as happy and as
  tired (sleepy), starving (heavy lids and the bowl), night (lower lids),
  the quick-finish nod, oops, side-eye, needs-you tapped (a nod, raised
  above the bubble), the strip press (amber line), focus on (the focus icon
  during needs you), and the nod when answered on the Mac.
- **New in `life`:** idle blink (closed mid-blink), glance, bob (a happy
  squint), working glance (down at the work), hungry rumble (worried) and
  hungry peek (looking up).

Every row of BEHAVIORS.md §3 now has a golden: prompt → `base/working`;
the finishes → `behaviour/quick-finish-nod`, `moments/cheer-1..3`; a failure
→ `behaviour/fail-oops`, `fail-side-eye`; needs you →
`needs_you/rung1..3`, `plus-one-more`, `behaviour/needs-you-tapped`,
`answered-nod`; you and Boop → `behaviour/tap-wiggle`, `listening`,
`thinking`, `too-slow-shrug`, `feel-*`, `moments/stretch`, `yawn`; time and
the device → `behaviour/night`, `screens/strip-icons`, `base/reconnect`.

## Decisions (specs updated in the same commits)

- Attention wins: only the replies to you play over needs you, and no
  mumbles (BEHAVIORS §1, decision log).
- The device plays the nod on clearing, the fallback shrug, and the mood
  face on touch-and-hold, and sends a new `input` `feel` (BEHAVIORS §3,
  PROTOCOL §4, decision log).
- Sound cues are reported in `dbg.state` as `sfx` before F5 plays them
  (VERIFICATION §3, decision log).
- Backlight levels: 110 at night, 60 asleep, 40 asleep at night, 70 with
  no app, and 255 whenever something needs you (BEHAVIORS §2).
- Threads and stats both close after 10 s, and a tap on them returns to
  the face (UX §3).
- `status` every 60 s is F4 work, as PLAN.md places it.
