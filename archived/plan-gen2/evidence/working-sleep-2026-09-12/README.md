# Working and sleep visibility — 2026-09-12

Working now uses the existing sweating/brow pose from its first signal, including
light effort. Existing grinding tremble remains; no session-count scaling was
added. Completion and welcome-back expressions clear sweat/brows.

Resting sleep brightness rises from 28 to **72/255**. A sleeping panel tap or
primary-button boop shows its 1.4-second peek at **210/255** with normal face ink,
then returns to 72. Face-down nap remains 28, awake remains 210, inactivity dim
remains 90 and request brightness remains 255. No host/wire field changes.

## Verification

- Both normal and USB-only builds passed (`dev-visible-20260912`).
- **29 USB hardware tests passed:** 12 state/parameter/dim/motion cases and 17
  existing turn-moment cases. Sleep tap checks keep host state asleep while
  asserting the 72 → 210 → 72 brightness sequence; nap remains 28.
- **19 working/sleep screenshots** reproduced in two independent passes with
  identical decoded pixels. Affected goldens updated after equality validation;
  the contact sheet was visually inspected for face/caption/footer spacing.
- Three additional sleep screenshots verify normal versus dim face ink, with
  telemetry confirming the brightness commands (screenshots do not measure the
  panel's physical luminance): [rest](sleep-rest.png), [peek](sleep-peek.png),
  [after response](sleep-after.png), [states](states.json).

[Build log](firmware-build.txt), [device checks](device-checks.txt),
[contact sheet](contact-sheet.png), [capture run](capture-result.json),
[capture output](capture-checks.txt), [image hashes](sha256.json).

The first combined run passed all 29 tests, then the screenshot script advanced
its frozen clock before the physical-button double-tap delay delivered the boop.
The capture was corrected to use the actual panel-tap injection path and let the
next loop apply brightness. The capture-only rerun passed; firmware did not need
another change. [Capture script](capture.py) requires reserved USB-only hardware.
No webcam was used, and the Mac app/LLM did not require rebuilding or new tests.

## Installed status

After verification the saved **normal dev-moments-20260912** image was restored,
with `usbOnly:false` and unchanged panic counter 103. Saved NVS/settings remain.
[Restoration](restoration.txt), [before](before.json).

The user quit the GUI and the normal **dev-visible-20260912** image is now
installed. Only the application and boot selection were written, preserving NVS.
Three startup samples verified normal mode (`usbOnly:false`), expected version,
increasing uptime through 10.5 seconds, unchanged panic counter 103 and no safe
mode. The successful normal image was retained as requested; this supersedes
the earlier restoration status. [Installation result](install-result.json),
[samples](installed.json), [retention](install-retained.txt).

The Mac app was not launched by the agent. The user receives the existing
worktree's `make run` command; live Bluetooth behavior after their launch is not
part of this startup check.
