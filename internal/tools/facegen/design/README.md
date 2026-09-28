# The animation pack

Release 2026-09-28 (V2), accepted by the owner: the device's faces, which
`facegen` turns into `firmware/assets/faces.h`, the popover's tiles and
the Mac's loop lengths ([plan/DEVICE.md](../../../../plan/DEVICE.md) §6).

- `svg/<mood>/<state>/<mood>.<state>.<nn>.svg`: 7 moods × 6 states, three
  variations each and working five. Asleep and no app look the same in
  every mood. The pack's `listening` state isn't here: v1 has no mic.
- `manifest.json`: the pack's catalogue, trimmed to these designs (each
  one's name, action, caption, length and path).

The contract is the pack's: what picks a design is the mood and the
state, and a variation is picked at random, never the last one
([plan/BEHAVIORS.md](../../../../plan/BEHAVIORS.md) §2). Working, idle,
asleep and no app loop; needs you's performance plays once and holds its
pending pose; the cheer (task complete) plays the loops the brain picks.
The pack's procedural sounds, its browser player and its build scripts
aren't used yet, and stay with the pack.
