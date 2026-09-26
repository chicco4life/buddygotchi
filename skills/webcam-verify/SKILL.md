---
name: webcam-verify
description: Verify Boop's physical screen and animations using bounded webcam recordings and consecutive-frame review. Use only when the user explicitly requests webcam verification; never activate for ordinary testing, animation edits, or a connected device alone.
---

# Opt-in webcam verification

This is a repository-local skill for Boop, and the one procedure for the
camera. The recorder's commands, what it writes, camera permission (record
from a terminal the Claude app opens) and its limits are in
`tools/webcam/README.md`.

## Activation

- Only use on an explicit request such as “use webcam verification” or
  `$webcam-verify`. General requests to verify changes do not enable the camera.
- Before a live recording, the user must confirm the board is positioned for
  the current verification session. Accept an existing “ready” confirmation in
  that session; do not ask again for each clip. If setup has ended or this is a
  later session, obtain fresh setup confirmation. Previous camera permission
  and earlier recordings are not standing authorization to record.
- Record bounded clips for the requested scenarios, then stop. No background
  monitoring, automatic future captures or webcam requirement in normal tests.
  Offline review of supplied recordings does not require camera setup.

## Verification

1. Discover cameras (`tools/webcam/webcam.sh list`) and explicitly select
   the intended one. Take a short framing clip and inspect `preview.png`
   (or run `tools/boopctl cam frame --camera ID`). If the display is out of
   frame or unreadable, ask for repositioning before recording the scenarios.
2. Choose natural app/Bluetooth operation or controlled USB injection. For USB,
   check `tools/boopctl ping` (`dbg.ping`, `plan/VERIFICATION.md` §3): `ble`
   must not be `conn` and `link` must not be `ble`, because a connected Mac
   app's `state` messages replace yours (L2's one-writer rule). Don't launch
   the app to fix it; ask the owner. Run the clock
   (`tools/boopctl send '{"t":"dbg.clock","run":true}'`) and avoid
   frozen-clock screenshots during recording. `tools/boopctl cam clip <name>`
   records and crops the L3 presets itself; for anything else, drive the
   board with `tools/boopctl play …` or `send` while recording. Record the
   installed firmware's `fw` and `sha` from `ping`; do not assume it matches
   the checkout or flash it merely to use this skill.
3. Start video-only recording before triggering the requested motion. Wait for
   `RECORDING`, retain scenario events, and use actual video timestamps for onset
   and duration; the host callback and requested clip duration are approximate.
   Restore temporary device state after the scenario where practical.
4. Crop the screen and inspect every consecutive frame covering the motion and
   settling. Compare against `plan/UX.md`, `plan/BEHAVIORS.md` and the
   simulator's golden images (`plan/VERIFICATION.md` L3). Account for physical screen
   orientation, exposure, camera cadence and display scanning. State explicitly
   when review used image sequences without real-time playback. Check
   continuous motion, overshoot and settling, repeated or abrupt jumps and the
   return to rest, allowing for the camera's frame quantization (about 33 ms
   at 30 fps). Clean timestamps alone cannot certify smoothness; ambiguous
   visual artifacts are inconclusive.
5. Report what was observed, the firmware identity, capture quality, limitations,
   and evidence locations, in a `review.md` beside the evidence: scenario,
   what moved when, deviations from the spec, and pass, fail or inconclusive. Keep original room footage local and out of Git;
   retain only deliberately selected evidence in the repo. Do not silently turn
   a limited scenario review into a full hardware pass.

The first live example is kept at the tag:
`git show gen2-final:archived/plan-gen2/evidence/webcam/2026-09-10.md`.
The v1 webcam checks (framing, test pattern, clips) are defined in
`plan/VERIFICATION.md` §5 L3 and §6, and driven by `tools/boopctl cam`.
`make tools-test` tests the tooling with synthetic video and does not open a
camera; it can run without activating live webcam verification.
