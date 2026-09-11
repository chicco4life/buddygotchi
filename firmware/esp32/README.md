# Boop ESP32 firmware

RenderState v2 firmware for the Waveshare ESP32-S3-Touch-AMOLED-1.64
(`ws-amoled164`, 456×280 landscape). The Mac supplies state; the device renders
its face, attention, optional text, completion notices and thread/history pages.
The board has touch and motion sensing, but no speaker.

Start with [device behavior and controls](../../plan/UX-DEVICE.md),
[shared state/trigger tables](../../plan/BEHAVIORS.md), and
[current verification status](../../plan/PLAN.md). Approvals stay in the editor;
device cards are passive and have no approve/deny controls.

## Build

From this directory:

```sh
tools/pio_ws.sh run -e ws-amoled164
# Independent USB UI verification; the Mac GUI may stay open:
tools/pio_ws.sh run -e ws-amoled164-usb-debug
```

The wrapper uses worktree-local, ignored `.platformio-core/` toolchains/cache and
`.pio/` build output. Keep the pinned platform in `platformio.ini`. The first
build downloads dependencies; cached builds reuse them. No separate asset
filesystem upload is needed. Waveshare is the only supported board; the retired
M5StickC Plus 2 and previous product remain under `archived/`.

## Verify on hardware

Reserve flashing/tests through `tools/dev/device.py` from the repository root.
Use `--usb-only` with setup and restoration scripts for the debug build; the
runner checks `ping.usbOnly=true`. Follow the
[shared-device workflow](../../tools/dev/README.md#shared-esp32).

Return to normal firmware afterward; never publish the debug image. Production
Bluetooth checks use normal firmware and one identified, user-launched Mac app.
USB screenshots and injected buttons do not prove Bluetooth integration.

Inside a reserved session, `tools/shots.py` captures all scenes, or
`tools/shots.py --only greet-3` captures one. Recipes modify the device snapshot,
so restore it afterward. Frozen-clock captures are deterministic; physical holds
and watchdogs still use real elapsed time. See [Verification](../../plan/VERIFICATION.md)
for HIL commands, screenshot review, motion and heap checks. Webcam verification
requires explicit permission and physical setup for that session.

## Implementation map

| File | Responsibility |
| --- | --- |
| `firmware/data.h` | Bounded frame parsing and live-data state |
| `firmware/main.cpp` | Screen priority, input handling, presentation timers and rendering |
| `firmware/glance.h` | Completion notices and thread/history navigation |
| `firmware/face.h`, `firmware/anim.h` | Face poses, easing and deterministic drawing |
| `firmware/palette.h` | Colours for the RGB332 canvas |
| `firmware/presence.h`, `firmware/clock.h` | Link presence and presentation clock |
| `firmware/hal/` | Board display, touch, buttons, IMU and power |

BLE, OTA and crash recovery retain their transport/board modules. The canvas
lives in PSRAM; screenshots use RGB565LE plus CRC32. Text uses the bundled
Korean-capable font. Sound motifs are scheduled but `halTone` is a no-op here.
Wire fields, compatibility-only diagnostics and commands are in
[PROTOCOL.md](PROTOCOL.md), with the host contract in [Wire v2](../../plan/WIRE-V2.md).
