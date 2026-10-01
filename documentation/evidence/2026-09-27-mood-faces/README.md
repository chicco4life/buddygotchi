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

## Part 2: the screen draws them

The device's face is now the mood design for Boop's mood and what it's
doing, and the old face (`render/face.*` and the poses in `render/anim.*`)
is gone. [device-screens.png](device-screens.png) has nine of the
simulator's new goldens: idle, working, asleep, no app, needs you with
"+1", the cheer, a tap's wiggle, a mumble over the cheer, and 100 ms into
the blink that hides a switch.

- **What the device adds** ([UX.md](../../UX.md) §2): its own blinks, a
  150 ms blink at every switch of design (and at a new cheer over a
  cheer), the tap's 3 px sway and heart, the press's 2 px dip, the bubble
  taking the props' band, and the talking "o". Who needs you moved from
  the bubble into the strip.
- **`make fw-test`:** 105 pass. The behaviour tests now check the scenes:
  after any change the design carries on at the same moment of its clock
  or the eyes are shut (every state × what's playing × every message or
  input); each look shows its design in the mood; the cheer keeps its
  clock when the mood changes mid-cheer; the wiggle keeps the look's
  clock; no app holds past the clock's wrap. The device tests: a frame
  is drawn only when the picture changes (a step that holds its place
  doesn't count), the 16 ms cap, and a press showing on its own ms with
  the clock running as frozen. The old face's 19 drawing tests went with
  it; `test_scene` covers the designs.
- **`make sim`:** all 36 pictures changed; each was looked at before
  `boopctl sim --accept`. The first run showed the cheer's sparkles under
  the bubble, since they sit outside the card's group in the SVG; facegen
  now counts a loose group drawn only in the props' band as a prop.
  After accepting: 10 scenarios, 0 expect failures, 0 changed pictures.
- **`make fw`:** builds; RAM 14.0%, flash 56.0% (1.10 MB, up 17 KB).

Not run: the board over USB (L2), and nobody has watched the designs
move on it (PLAN.md, owner check 1).

## Part 3: the popover's face

The popover's face tile now shows the face of the same design as the
device, for Boop's mood and look, from `app/Boop/Views/FaceDesigns.swift`,
which `facegen` writes alongside `faces.h`. The old hand-copied face
(`FaceGrid`, `FacePose`, `FaceBlocks`) is gone; the menu-bar icon is
unchanged. [popover-tiles.png](popover-tiles.png): the working overview
in the determined mood (a new snapshot fixture), and setup's cheeky
preview, the proud idle face.

The Mac draws the designs' exact colours. The device keeps its inks,
which were already the nearest RGB565 colours to them: setting them to
the designs' values made the panel's truncation land further away (the
eyes' red at 255 for 248), which the simulator showed as a change in
every golden.

- **`make build`** and **`make test`:** pass.
- **`Boop --snapshots`:** 42 PNGs, contrast passes.
- **`make fw-test`** and **`make sim`:** unchanged (105 pass; 0 changed
  pictures).
