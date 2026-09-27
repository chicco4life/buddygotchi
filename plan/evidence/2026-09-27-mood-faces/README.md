# The mood designs on the device (A11), 2026-09-27

The designer's 49 animated SVGs, one for each mood and state
(`internal/tools/facegen/design/`), drawn by the device exactly as Chrome
draws them. [designs-vs-device.png](designs-vs-device.png) shows the
device's faces before this work (top row, from the simulator's goldens)
above every design, 2.5 s in.

## Part 1: the generator and the player

`internal/tools/facegen/facegen.py` reads each SVG as rectangles in
groups, with step-wise moves and show/hide timings, and writes
`firmware/assets/faces.h`: 30 distinct scenes (the 7 moods × idle,
working, needs you and task complete, and one asleep and one no-app scene
shared by every mood), 1860 rectangles, 107 tracks, about 21 KB.
`listening` is left out, since push-to-talk is gone. `render/scene.h`
draws a scene at any moment on its own clock, with the device's additions
on top: a blink, the prop making room for the bubble, the talking mouth,
and the face moving as one. The screen doesn't use it yet.

- **`make faces`** (`facegen.py --check`): 337 frames of the 30 scenes,
  at up to 12 moments each away from any step, match Chrome's drawing of
  the SVGs pixel for pixel. The only non-straight line in the set, the
  result card's folded corner, first differed by 8 pixels: a pixel whose
  centre sits exactly on a diagonal belongs to the shape on its left in
  Chrome, and facegen follows that.
- **`make fw-test`:** 123 pass. New, `test_scene`: the player draws all
  337 frames as facegen does (CRC-32 of every pixel's colour); asleep and
  no app are the same in every mood; a blink shows the closed eyes; the
  keyboard makes room and the face doesn't change; the talking "o"; the
  face moving as one; frames change only when a step or an addition does;
  gestures that play once hold their last step.
- **`make fw`:** builds; RAM 13.9%, flash 55.1% (the player isn't linked
  in until the screen uses it).
- **`make sim`:** 10 scenarios, 0 changed pictures.
