# Compact footer and USB-only verification

Board: Waveshare ESP32-S3 Touch AMOLED 1.64, 456 × 280 logical canvas.
The test image is `dev-footer-usb-20260910`; the normal image is
`dev-footer-20260910`. Both build successfully. The USB-only stubs are
excluded from normal firmware; no Mac app lifecycle changes are involved.

## Checks

- Five host workflow tests pass: hardware reservation/delegation, restoration
  after scenario failure, USB-only identity acceptance/rejection, and rejecting
  normal firmware without running a scenario while still restoring.
- The animation-clock source guard passes.
- Fourteen distinct targeted hardware cases pass across runs: approval arm
  guard, all three stakes, hold-to-deny, acknowledgement behavior, next-card
  priority, frozen screenshot integrity, and no rendered dots in six states.
- Zero-dot verification checks the returned state, not just pixels. No alert
  is represented by omitting `dotAlert`, not by sending `-1`.
- The Mac GUI remained open during USB-only testing. This is independent
  device/UI evidence, not Bluetooth integration evidence.

## Capture recipes

`capture.py` uses the existing `shots.py` pipeline for static scenes, with
UTF-8 byte-cap checks for its fixtures. It also captures hold progress,
early release, sending, and acknowledgement. Run it under the USB-only
reservation with setup/restoration scripts; see `tools/dev/README.md`.
Do not open a camera: these are the device's framebuffer screenshots.

The initial idle comparison rewound the clock before frame receipt and
therefore changed the connection glyph. The corrected test freezes forward
from receipt. Initial oversized text fixtures were rejected by the firmware;
those fixtures were corrected, not used as evidence of successful rendering.

Hardware run logs are in `/tmp/boop-footer-usb-run-2`,
`/tmp/boop-footer-usb-run-4`, and `/tmp/boop-footer-usb-captures` on this machine.
Backups remain local in `/tmp/boop-footer-artifacts`; they are not committed.

## Visual review

All static captures were reviewed: prompt left, persistent controls right,
queue count, long English/Korean glosses, and ellipsis on long tool names.
Hold progress, early release, sending, and acknowledgement were reviewed.
Framebuffer pixel checks confirm the face remains present in every static
and feedback capture. The three affected approval goldens were refreshed
from the standard capture recipes. The panic counter stayed at its baseline
101 throughout the successful USB run.

The successful capture log is `/tmp/boop-footer-usb-review`.

## Final device state

The runner finished successfully (setup, scenario, and restore all exit 0).
Saved flash state was restored before installing the reviewed normal image.
Final USB ping confirms `fw=dev-footer-20260910`, `usbOnly=false`, contract 2,
and panic counter 101. The hardware reservation is released.
