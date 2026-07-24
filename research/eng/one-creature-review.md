# One-Creature Pass — Review Guide

What shipped in commits `9c539d1` + `1b51f23` (2026-07-22), what it does, how it
works, and how to test each piece by hand. The theme: the Pebble and the Mac
blob stop being two pets that happen to share data and start acting like one
creature.

Everything below is flashed on the Pebble and running in the app build.
Machine-verified: USB HIL 34/34 on hardware, BLE e2e proven, HTTP e2e 40/40,
app unit tests 144 green. Human-verified so far: shake, flip-nap. Waiting on
you: button feel (Saturday), power-down hold, petting-by-finger.

---

## 1. Boops bridge to the desktop (heart state, end-to-end)

**Behavior:** boop the device — BOOP button outside a prompt, or a touch —
and *both* pets flash heart-eyes for ~2.5s, then return to whatever they were
doing.

**How it works:**

- Firmware `boopPet()` (`firmware/esp32/firmware/main.cpp`) sends
  `{"cmd":"boop"}` upstream over BLE + serial, rate-limited to one frame per
  ~1.5s so sustained petting doesn't spam the link.
- The app (`BLEManager` → `ESP32Output` → `BuddyEngine.boop()`) reduces it to
  a ~2.5s `affectionUntil` window (`BuddyReducer.swift`), which overlays a new
  `PetState.heart` on the calm states only — **attention, error, and sleep
  always win**. The base state's `msg`/activity context survives the flash, so
  a busy pet goes right back to "running npm test" afterwards.
- The heartbeat then carries `pet:"heart"` back to the device (`derive()` maps
  it to `P_HEART`), which is what keeps the two faces in lockstep — the
  device's local flash and the desktop's mirror agree on timing.
- Mac visuals: `BlobBuddyView` heart-eyes (SF `heart.fill`), pink blush,
  fluttery glow pulse; new `BuddyTheme.boopPink`; status pill shows pink
  "heart".

**Try it:** with the app connected, press BOOP (or tap the screen) while the
pet is idle/busy. Watch the Mac popover flip to heart in <1s and back ~2.5s
later. Then trigger a real approval prompt and boop — the card must stay, no
heart (doctrine: urgency beats affection).

## 2. Touch is real petting

**Behavior:** a tap is a boop; *holding or stroking* keeps the heart alive for
the whole stroke (device and Mac), and the heart face rains little drifting
mini-hearts past the cheeks. Petting a sleeping pet does the one-eye
sleep-peek for as long as you stroke, without waking him.

**How it works:** the touch-hold path refreshes `boopUntil` every loop and
re-sends the upstream boop on the 1.5s rate limit, so the desktop's 2.5s
window keeps sliding. Mini-hearts are deterministic-phase particles in
`face.h` (no `rand()`, so HIL screenshots stay reproducible).

**Unchanged doctrine:** touch can never approve, deny, open the menu, or act
while a prompt is pending. Only physical buttons decide.

**Try it:** stroke the screen for 5s — heart should persist the entire time on
both pets, hearts drifting. Stroke the sleeping face — peek, no wake.

## 3. Motion (QMI8658 accelerometer) — nap and dizzy

**Behavior:**

- **Flip face-down for 2s → nap.** Screen goes dark, stays dark, and nap time
  accrues into the `napSeconds` stat — the menu's "naps Xm" line is finally
  real data. Flip face-up (700ms debounce) → wakes.
- **Shake → dizzy.** X-eyes wobble face for ~3s, with the dizzy chirp.

**How it works:** minimal QMI8658 driver in the WS HAL
(`hal_ws_amoled164.cpp`) — probes 0x6A/0x6B on the shared touch I2C bus, ±4g
@ 125Hz, polled at 20Hz. Detection lives in `motionTick()` in `main.cpp`:
face-down = panel-normal axis < −0.75g (sign verified on hardware: resting
panel-up reads +0.9g); shake = leaky accumulator over |magnitude − 1g|.

**Doctrine + safety rails (the field fixes live here):**

- Motion is **display-only** — can never answer a prompt. Shake is suppressed
  while a prompt is pending; nap entry is blocked too.
- Touch is ignored while napping (a couch pressing the screen can't boop).
- **Nap can never trap the pet** (this was the "frozen pet" you hit):
  - IMU reads back off 500ms on I2C errors instead of hammering a flaky bus
    at 20Hz (the driver-error serial spam alone read as glitchy).
  - If the sensor goes silent >5s mid-nap, the nap fails open and the screen
    returns.
  - **Any physical button press ends a nap instantly**, and restarts the 2s
    face-down debounce so you get real lit-screen time (not a 50ms re-nap).

**Try it:** you already did — plus new: while napping, press BOOT; screen must
come back immediately. Check the menu stats screen after a few naps.

## 4. Power-down ("night night")

**Behavior:** hold BOOP — at 1.5s the screen sleeps, keep holding to 4s and
the pet says **"night night"** and powers down. Press BOOT to wake (fresh
boot). Works from a dark screen too — that was the field fix: the wake-press
guard now eats only *taps*, never *holds*, so the overnight case (screen off,
exactly when you want to power down) works.

**How it works, and two hardware-shaped decisions worth knowing:**

- On the Pebble this is **light sleep + restart**, not true deep sleep:
  GPIO0 (BOOT — currently the only wake button) is the ESP32-S3 boot strap,
  and a true deep-sleep wake samples the straps while your finger is still
  down — the ROM would drop into the serial downloader and the device would
  look dead until RST. Light sleep wakes without a strap sample; the wake
  path also waits for the press to end before `esp_restart()`. The M5 build
  gets true deep sleep (its BtnA/GPIO37 isn't a strap).
- Going down, BLE is quiesced by **stopping advertising only** —
  `BLEDevice::deinit` under a live link corrupts the heap on the NimBLE
  core-3 wrapper (found when the Mac re-authed mid-teardown and the device
  panicked; caught by the HIL round-trip test). The BT *controller* is
  disabled at the lowest level right before sleep instead.
- Physical presses only: synthetic `press a --ms 5000` can never power down,
  so HIL can't strand the device. Tests use `deepsleep <ms>` (timer wake).

**Try it:** hold BOOP 4s from a lit screen *and* from a dark screen — both
must reach "night night". Wake with a BOOT tap. Battery draw in this mode is
light-sleep-level (~1–2mA), not true deep sleep — acceptable for now, and
revisit-able once IO1 exists as a non-strap wake pin.

## 5. Buttons (your Saturday checklist)

Wiring: momentary switches from header holes **1** (boop), **2** (reject),
**5** (menu) to **G**, no resistors (internal pull-ups). Pins have been live
since the HAL landed — zero firmware changes needed. Then:

1. Short-press 1 → heart on both pets.
2. `mockprompt` over serial (or a real agent prompt) → press 1 = "yes!",
   press 2 = "okay". Confirm the 600ms arming window: a press already down
   when the card appears must not count.
3. Press 5 → menu opens; 5 = next, 1 = pick, 2 = back; 10s auto-close.
4. Hold 1: 1.5s screen off → 4s night night. **Wake is BOOT-only until IO1
   is added as a wake source — ping me when buttons are on and I'll make
   that change** (IO1 isn't a strap pin, so it also removes the BOOT wake
   caveats).
5. While napping, press any button → screen back instantly.

## 6. Where things live

| Piece | Files |
| --- | --- |
| Heart state, affection window | `app/Boop/Core/BuddyState.swift`, `BuddyReducer.swift`, `BuddyEvent.swift`, `BuddyEngine.swift` |
| Boop over BLE | `app/Boop/Outputs/ESP32/BLEManager.swift`, `ESP32Output.swift` |
| Mac heart visuals | `app/Boop/Buddies/BlobBuddyView.swift`, `Views/PetStageView.swift`, `Views/PopoverView.swift`, `Theme/BuddyTheme.swift` |
| Boop emit, petting, motion, power-down, ladder | `firmware/esp32/firmware/main.cpp` |
| Heart face + mini-hearts | `firmware/esp32/firmware/face.h` |
| IMU driver, light-sleep, I2C backoff | `firmware/esp32/firmware/hal/hal_ws_amoled164.cpp` (+ `hal.h`, `hal_m5stick.cpp`) |
| BLE quiesce | `firmware/esp32/firmware/ble_bridge.{h,cpp}` |
| Wire protocol | `firmware/esp32/PROTOCOL.md` (`{"cmd":"boop"}`, `pet:"heart"`, new serial debug cmds) |
| Tests | `app/Tests/ReducerTests.swift` (7 boop tests), `firmware/esp32/tests/hil/test_usb.py` (7 new HIL tests) |

Debug/serial additions: `imu`, `imu set x y z`, `imu clear`,
`deepsleep [ms]`; `state` grew `boop` / `napping` / `dizzy` / `ladder` /
`touchOk` / `imuOk`.

**If touch or motion ever "just stops":** check `state` → `touchOk`/`imuOk`.
The FT3168/QMI8658 probes used to be one-shot at boot (a miss = dead sensor
until reboot, with the log line dropped because it printed before
Serial.begin); they now log visibly and re-probe every 2s/5s until the chip
answers, so a wedged sensor self-heals.

## 7. Known gaps / deliberate cuts

- Blob-only by design this pass — no species work, no accent-color work.
- Boop stats aren't counted or surfaced anywhere yet (naps are).
- The desktop can't boop the device (affection is one-directional, device →
  desktop; the mirror-back makes it *look* mutual).
- Power-down wake = BOOT only until IO1 is soldered + added as wake source.
- Battery untested (no cell yet) — polarity check + ≥1000mAh cell notes in
  `waveshare-amoled-port.md` §board profile.
- Shake/nap thresholds were tuned via injection + your one hand-test; they
  may want a feel pass (constants at the top of the motion section in
  `main.cpp`: `FACE_DOWN_G`, shake threshold 2.5, decay 0.8).
