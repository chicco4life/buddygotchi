# Boop v1 build: report

> **Since this report (2026-09-26).** F6, a landscape screen and cuter
> eyes, came after it at your request. It's in progress: the board runs the
> landscape build and matches the simulator, and it waits for your look and
> a new touch calibration (morning checklist rows 2–3). There are now 83
> goldens in 11 scenarios (80 at handoff), and the screen is landscape
> (`kRotation` 1 in `firmware/src/board/display.h`). See
> [PLAN.md](../../PLAN.md) §4 and the [F6 evidence](F6/README.md).
>
> **Cut to the minimal surface (C1, 2026-09-26).** After that, v1 was cut
> down at your request. Mood, XP and hunger, night, focus, the nudge
> ladder, cheer sizes, the threads and stats screens and the brain's faces
> are parked (code at tag `v1-full`). The goldens are now 45 in 10
> scenarios. Where this report describes those features, it's history. See
> [BEHAVIORS.md](../../BEHAVIORS.md) and the
> [C1 evidence](../2026-09-26-minimal-cut/README.md).

The unattended build ran on 2026-09-26 on branch `v1-overnight`, starting
from tag `gen2-final`. Every milestone except P1 has passed; P1 waits for
you. A3 passed under your 05:36 ruling, with known issues. The running log
is [PROGRESS.md](PROGRESS.md), and each milestone has its own README.

## In short

- **Works, checked here:** hooks from Claude Code and Codex reach the board
  over USB in under 100 ms (p95), with every checkpoint passing on both
  brains. The face, screens and behaviour match the simulator pixel for
  pixel on all 80 goldens. A 31-minute soak with Apple's model had no
  resets, no leaks and nothing stuck. Voice timing is right on the board.
- **Not checked here, because it needs you:** Bluetooth between the Mac and
  the board, the menu-bar app and its setup window, push-to-talk with the
  real mic, touch accuracy and the physical buttons, and hearing the voice.
  The morning checklist covers all of them.
- **Webcam:** used for F1, F2, F3 and J1, then switched off by you at 05:36.
  No L3 check ran after that (A3, F5, J2, J3), and none of those is counted
  as passed.

## Milestones

| # | Milestone | Status | Evidence | Headline |
| --- | --- | --- | --- | --- |
| M0 | Setup | Passed | [M0](M0/README.md) | Gen-2 code deleted (kept at `gen2-final`); new SwiftPM and PlatformIO projects; `boopctl`; Makefile |
| F1 | Board bring-up | Passed | [F1](F1/README.md) | Panel settings confirmed by webcam; 160 KB free before Bluetooth; device screenshots identical to the simulator; 460800 baud (the CH340 fails at 921600) |
| F2 | Renderer and simulator | Passed | [F2](F2/README.md) | Warm Terminal palette, Geist Mono, procedural face; 58 goldens reviewed; min 44 fps during blends; webcam clips reviewed |
| F3 | Device behaviour | Passed | [F3](F3/README.md) | Idle life, needs-you ladder, moments, gestures; every BEHAVIORS §3 row has a golden; 20-minute soak with no reset; webcam clips reviewed |
| F4 | Bluetooth on the device | Passed | [F4](F4/README.md) | Nordic UART as `Boop-54FE`; heap 84 KB advertising (target 60 KB); scenarios and soak unchanged with Bluetooth on. A real connection is for you |
| A1 | App core | Passed | [A1](A1/README.md) | `boop-hook` exits in ≤ 9 ms with no app; adapters and core rules with a test per BEHAVIORS row |
| A2 | Memory, Voice, actions | Passed | [A2](A2/README.md) | Memory limits and snapshots; 10,000 gibberish lines with zero dictionary hits (doubles rule changed, see below) |
| A3 | Harness and brains | Passed (your ruling) | [A3](A3/README.md) | Speech limited in the harness. **The L5 action-drop check failed in 2 of 3 runs** (5.5%, 6.8% against 5%), all from the deferred reflection issues |
| A4 | Device link, app shell, push-to-talk, installer | Passed | [A4](A4/README.md) | Headless app drives the board over USB; installer tested on a temporary HOME; doctor rewritten. The menu-bar app and mic are for you |
| J1 | End to end over USB | Passed | [J1](J1/README.md) | Hook to board p50 72 ms, p95 91 ms; both brains pass every checkpoint; found and fixed brain moments cutting off the rules' cheer |
| F5 | Voice on the device | Passed | [F5](F5/README.md) | 226 KB of voice assets; the DAC's timing within 0.4% of `say`; nobody has heard it (no speaker) |
| J2 | Soak and polish | Passed | [J2](J2/README.md) | 31.2-minute soak with Apple's model: 962 hooks, 0 misses, no reset, heap drift 0; README rewritten |
| J3 | Handoff | Passed | [J3](J3/README.md) | This report; `boopctl calibrate` added; final firmware flashed |
| P1 | Port to ESP-IDF + LVGL | Not started | | Waits for you, by design |

Nothing was blocked. A3 was blocked once (L5 over-speaking) and reopened
by your 05:36 decisions.

## Changes to the spec along the way

Every one is in the decision log (ARCHITECTURE.md §11). The ones you're most
likely to notice:

- **460800 baud** over USB, not 921600 (the CH340 bridge fails at 921600).
- **Doubled syllables** (`ki-ki`, `ba-ba`) skip the big word list in the
  gibberish check, since most of them are in it; a short list of doubles
  that read as words (`mama`, `papa`, …) still fails (VOICE.md §7).
- **Attention wins:** while something needs you, only `nod`, `listening`,
  `thinking`, `shrug` and `zip` play, and no mumbles.
- **The device plays** the nod when "needs you" clears, the shrug when
  push-to-talk gets no answer, and a mood face on touch-and-hold (new
  `input` `feel`).
- **Brain speech limits in the harness:** `say` at most once per 10 minutes
  on events (never on a turn start), once per 5 minutes on taps.
- **Brain moments wait** for the rules' moment to finish (J1's bug).
- **Touch calibration** is an affine map fitted by `boopctl calibrate` and
  kept in NVS (J3).

## Known issues

From A3 (tuning the brain, deferred by you):

1. `note` on talk: notes praise and greetings, and sometimes skips a real
   fact ("remember I ship on Fridays").
2. The filler word `tests` in most spoken lines, taps included.
3. A `moment` nearly every reflection, usually a retelling that the action
   refuses. This is what pushes the drop rate over 5%.
4. Apple's guardrail refuses about 2 of 52 triggers ("jetpack is the
   payments service"). They're dropped, and Boop keeps the rule reaction.
5. `remember("jetpack = payments")` is refused by memory's code check
   because of the `=`. Either steer toward words, or let a lone `=` through.
6. Sometimes two faces in one answer on events. Harmless (one plays).

From the device and the link:

7. **USB drops bytes now and then** from the board to the Mac (J2: two
   lost debug replies and 23 missing characters in a 31-minute run). There
   are no sequence numbers, so a lost line (a tap, say) is gone. Bluetooth
   is the everyday link and doesn't use the CH340. Options: number the
   board's lines, or drop to 230400 baud.
8. **With no app, the board shows the no-app face** (sleepy eyes, plug icon,
   dimmed) after 30 s. That's the spec, but it means "leave it on the idle
   face" can't hold without the Mac talking. The board is on firmware
   `1.0.0` and shows the no-app face now; it will show the idle face as
   soon as the app connects.
9. Heap is 73 KB free with Bluetooth and voice (target 60 KB), so about
   13 KB of headroom.
10. The first launch of a freshly built `boop-hook` takes about 250 ms
    (macOS checking the new binary). Later launches are 5–30 ms.
11. The Codex fixtures are synthetic: no real Codex approval was recorded.
    The tool name `shell` with an argv `command` is an assumption.
12. The RGB LED is on the board's back. Red and blue were seen on the
    webcam; green and amber were checked only in `dbg.state`.
13. The battery ADC's 2:1 divider is assumed. With no battery it reads the
    charger's ~4.16 V.
14. SPI runs at 40 MHz. Faster wasn't needed (44+ fps), so it wasn't tried.
15. Your `~/.claude/settings.json` and `~/.codex/hooks.json` still have the
    gen-2 `~/.boop/boop-hook.sh` entries. Nothing here touched them; the v1
    setup window replaces them.

## Confirmed panel settings

Confirmed on the real panel with the test pattern and the webcam (F1), and
in `firmware/src/board/display.h`:

| Setting | Value |
| --- | --- |
| Controller | ST7789 on SPI2 (SCLK 14, MOSI 13, CS 15, DC 2), no reset pin |
| SPI write clock | 40 MHz |
| Colour inversion | On |
| Colour order | RGB |
| Rotation | LovyanGFX 0: portrait, the top is away from USB-C (portrait at handoff; landscape since F6) |
| Offsets | 0, 0 (240×320) |
| Backlight | PWM on GPIO21 at 12 kHz |
| Touch | XPT2046 on SPI3 (25/32/39/33, IRQ 36). **Not calibrated yet**: run `boopctl calibrate` |

## The morning checklist: what's different

PLAN.md §6 is updated to match. The changes:

- **Row 2:** expect the **no-app face** (sleepy, a plug icon, dim, slow
  blinks), not the idle face. It becomes the idle face once the app
  connects (row 6).
- **Row 3:** `tools/boopctl calibrate` is new (J3). It shows 4 amber crosses
  near the corners, one at a time, then one in the middle to check. Tap
  each with a fingertip or stylus and lift. It prints `check_miss_px`: a
  few pixels is good; over about 10 means try again. `--show` prints the
  stored map, and `--show --clear` goes back to the default range. The
  maths and the board's storage were checked here (it survives a reflash),
  but it has never had a real tap.
- **Row 4:** do the status-strip tap **after row 6**. On the no-app screen,
  a strip tap doesn't open threads or stats (the no-app screen wins).
- **Row 10:** the brain's mumble will probably use the word `tests`
  (known issue 2).
- Nothing on the checklist has run yet. Rows 16 and 17 (the voice) are
  still unheard by anyone.
