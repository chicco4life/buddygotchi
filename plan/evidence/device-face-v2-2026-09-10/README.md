# Larger, lower approval face

Waveshare ESP32-S3 Touch AMOLED 1.64, 456 × 280. Firmware `dev-face-v2`.

The approval face is 22 px lower than the compact-footer baseline, with eyes
20% wider and taller. Footer text and button behavior are unchanged.
Both normal and USB-only builds pass, as does the animation-clock source guard.

Captured all three stakes, hold progress/release, sending, and confirmation
through the USB-only reservation while the Mac app remained open. Reviewed
spacing and confirmed no text overlap. Panic count stayed at 101. The three
approval goldens were refreshed. This is UI evidence, not BLE integration evidence.

`capture.py` reproduces the scenes using the standard screenshot pipeline;
run under the USB-only device wrapper with setup and restoration scripts.
Run logs: `/tmp/boop-face-v2/run`. Previous screenshots are in
`../device-footer-2026-09-10/`.

Saved device state was restored and normal `dev-face-v2` firmware installed,
verified with `usbOnly=false`. Setup, scenario, and restoration all exited 0.
