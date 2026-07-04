# 10 — Pass 2: Firmware Deep Dive (new scope)

First full audit of `firmware/esp32/`. Architecture verdict: the "pure renderer" direction (commit `1b1de9e`) is right and matches the product doc ("the Mac app is the brain"). But the refactor left the file half-migrated: a large orphaned UI layer, heritage branding on user-visible screens, and several product-level gaps (no dim/sleep, no sounds) that the old code used to cover. The BLE/OTA transport layer, by contrast, is in good shape (LESC+MITM bonding, encrypted characteristics, safe OTA with hash verify and abort-on-failure).

## 1. Dead code: ~700 lines of `main.cpp` are unreachable

`loop()` renders exactly: passkey screen | OTA screen | buddy + status lines. Nothing calls `drawMenu`, `drawSettings`, `drawReset`, `drawInfo` (6 pages), `drawPet`/`drawPetStats`/`drawPetHowTo`, `drawHUD`/`drawApproval` (the rich one), `drawClock`, `menuConfirm`, `applySetting`, `applyReset`, `nextPet`, `checkShake`, `isFaceDown`, `wake`, or the `menuOpen/settingsOpen/resetOpen/displayMode/napping/screenOff/dimmed/brightLevel/btnALong/msgScroll` state machine. Only `main.cpp.bak` (also committed!) wires them. Physical buttons currently do exactly one thing: approve/deny an active prompt.

**Decide and execute** (recommendation: delete, then rebuild the short list below deliberately):

1. Delete `main.cpp.bak` from the repo (it's in git history).
2. Remove the orphaned systems: menu/settings/reset UI, info pages, pet stats pages, HUD/transcript scroller (`wrapInto`, `msgScroll`, `tama.lines` consumers — note the desktop still sends `entries[]`; keep parsing but stop pretending there's a transcript UI, or resurrect the HUD deliberately), clock mode + orientation machinery (`clockUpdateOrient`, `drawClock`, `_clkTm/_clkDt` — unless the charging-clock feature is wanted for v1; it's a nice desk feature but it's dead today), shake/face-down/nap.
3. Keep: approval handling, synthetic press/serial debug (`ping/state/screenshot/press/btn/mockprompt` — the HIL tests depend on these), OTA screen, passkey screen, demo mode.

The pet-stats page deserves a special mention: it renders **hard-coded fake data** (mood 2/4 hearts, fed 0/10, energy 3/5, "Lv 0", tokens 0) — and the product doc explicitly rejects hunger/guilt mechanics (§10.2 "no hunger nags"). Even when resurrecting screens, this page shouldn't come back in this form.

## 2. Heritage branding is user-visible on the device

This firmware descends from `claude-desktop-buddy` (LICENSE + REFERENCE.md acknowledge it — keep the attribution). But product-facing strings still speak the old identity:

- **BT name `Claude-XXXX`** (`startBt()`): visible in the app's device picker, macOS Bluetooth settings, and every neighbor's scanner. Should be `Buddy-XXXX` (fits the 15-char adv name budget). Note: the Mac app scans by NUS service UUID, not name, so nothing breaks — but bump anyway; also update the onboarding pairing copy if it ever names the device.
- Info page 0: "I watch your Claude desktop sessions" → agent-neutral ("I watch your coding agents").
- Info page 4 pairing instructions: "Open Claude desktop > Developer > Hardware Buddy" — **points at the wrong application entirely**. Should be "Open Buddygotchi on your Mac > Settings > Displays".
- `data.h` disconnect message: `"No Claude connected"` → `"no agents awake"` (match the app's empty-state voice).
- Credits page: keep Felix Rieseberg + upstream repo attribution (license-appropriate), add Buddygotchi identity above it.
- `TamaState` naming, `personaNames` are internal — fine to leave.

(Several of these live in currently-dead `drawInfo` code — do the branding pass on whatever survives §1.)

## 3. Product gaps in the pure renderer

The old code paths that died carried real product requirements (PRODUCT.md §9.3, §10):

- **No display power management at all.** `SCREEN_OFF_MS`, `dimmed`, `wake()` are dead; brightness is fixed at `applyBrightness()`'s boot value. The device burns full brightness 24/7 — "asleep = dark" is the light language's fifth word, and an always-lit sleeping pet is wrong on a nightstand desk. Rebuild minimally: when `pet == sleep` for >60 s, ramp brightness to ~20 %; after 10 min, screen off (any state change or button wakes). When awake, brightness by state (attention full, idle medium). ~40 lines, driven from `activeState` transitions in `loop()`.
- **No sounds.** `beep()` exists and is only called from dead menu code; state transitions are silent. Implement the §10.3 motifs: attention = rising two-note "meep?", celebrate (≥30 s tasks — desktop already gates via `celebrate` flag + msg) = short trill, error = single low note. Respect `settings().sound`; since the settings menu is dead, honor a desktop-sent mute instead: add optional `"mute": true` to `RenderState` (additive, wire-safe) mirroring the app's Sounds toggle. Keep every motif ≤3 notes.
- **Long-press A = screen off/on** (the §10.1 "hold = sleep/wake" gesture) — cheap to support in the approval-button reader; guard against conflicting with approval taps (long-press only when no prompt is armed).
- Persona mapping nit: `thinking → P_HEART` (heart-eyes). Thinking should read as thinking — the species sets have busy/idle variants; a "…" overlay (the desktop blob uses one) or reuse of `P_BUSY` with a slower beat is closer to "calm, presumed alive" than hearts. Check what `buddy.cpp` renders for `P_HEART` and align with the desktop's thinking face.

## 4. BLE heartbeat can drop the largest frames

`data.h` line assembly uses `_LineBuf<1024>` for the BLE channel, but a fully-populated `RenderState` exceeds it: base fields+prompt ≈ 400 B, `entries` = 6 × (≤66 chars + JSON overhead ≈ 78 B) ≈ 470 B, `sessions` = up to 6 × ~70 B ≈ 420 B → **~1.3 KB worst case**. Overflowing bytes are silently discarded until newline → `deserializeJson` fails → the frame is dropped. The overflow happens precisely in the busiest multi-session states — the moments the device exists for. The firmware-side RX ring is already 2048 (`ble_bridge.cpp RX_CAP`), so:

- Bump `_LineBuf<1024>` → `_LineBuf<2048>` for `_btLine` (and `_usbLine` for symmetry). +2 KB RAM on a chip with ~100 KB free heap (per the info page) — fine.
- Belt-and-braces on the Mac side: `Heartbeat.renderState` already truncates `msg`/prompt/completed fields but not `entries` items or `sessions` labels — cap entry strings to ~48 chars and `lbl`/`tool` to 16 on the wire, and add a debug assertion that encoded heartbeats stay under 1.5 KB.
- Add a HIL test: push a max-fat heartbeat over BLE (`tools/buddyctl.py set` with 6 long entries + 6 sessions), then `state` and assert the fields arrived.

## 5. OTA: good bones, two improvements

`ota.h` is solid — next-partition write, streaming SHA-256, refuses low battery, abort-on-any-failure leaves the old image bootable, ack discipline matches the Mac's back-pressure. Remaining:

- **Throughput (carried from pass-1 06 §5).** Still 96-byte payloads with an ack round-trip each (`OTAProtocol.chunkPayloadSize = 96`, `_otaAck` per chunk) ≈ 9 min/MB. The decode buffer is already 256 B, and negotiated MTU is typically 185 — payload can rise to ~128 within the current everything (frame ≈ 30 B envelope + 4/3·128 = 201… too big; 110 fits) for a free ~15 %. The real win stays proto v2: `ota_begin` advertises `"proto":2`, chunks flow via write-without-response with an ack every 8th seq (device tracks last seq, acks with `n`), Mac pipelines. Version-gate on the begin-ack so old firmware keeps per-chunk acks.
- **Post-reboot version confirmation.** After `ota_end` + restart, nothing confirms the new image *is* the manifest version — `FirmwareUpdater` optimistically shows success after 5 s and `recordDeviceVersion` re-evaluates whenever the status reply arrives. That loop only works if FW_VERSION is injected correctly at build time (it isn't — see 11 §3). Once 11 §3 lands, add an app-side check: if post-reboot `deviceVersion` ≠ installed release version, surface "update didn't stick" instead of quietly flipping back to "Update available".

## 6. Smaller firmware items

- `bleWrite` sleeps `delay(4)` per ≤180 B notify chunk **on the render loop's thread** — a 1.3 KB heartbeat blocks the loop ~32 ms (2 dropped frames at 60 fps). Acceptable; worth a comment, and proto-v2 work shouldn't make it worse.
- `settings().bt` / `wifi` toggles are stored-only placebos (comments admit it) — they render as real switches in the (dead) settings menu. When rebuilding any settings UI, drop placebo toggles entirely.
- `drawApproval`'s "impatience" timer turns `HOT` at 10 s — nice detail, but it lives in the dead `drawHUD` path; the live approval strip in `loop()` has no waited-time indicator. Port the timer to the live path.
- `dumpScreenshot` + serial commands + `tools/buddyctl.py` + HIL pytest markers are a genuinely good test story — protect them in the §1 cleanup (they're the reason `make hil` works).
- `platformio.ini` pins `FW_VERSION "0.1.0"` — see 11 §3 for the CI injection; locally, `pio run` builds should get `-DFW_VERSION=\"dev\"`+ git SHA via a `extra_scripts` hook rather than a hardcoded lie.
- `stats.h` approvals/denials counters increment where? (`stats().approvals` renders in dead UI; verify `sendApproval` still bumps them — if not, either wire or delete with §1.)
- Wire-contract doc: `RenderState` ↔ `TamaState` field mapping now lives only in two source files. Add a short `firmware/esp32/PROTOCOL.md` table (field, max length, since-version) — the truncation limits on both sides (§4) become explicit contract instead of coincidence.

## Acceptance criteria

- `grep -c "drawMenu\|drawInfo\|drawPet\|drawClock" main.cpp` → 0 (or they're reachable again, per the decide-and-execute); `main.cpp.bak` gone.
- Device advertises as `Buddy-XXXX`; no user-visible string says "Claude" except the agent-name in prompt sources.
- A sleeping device dims within a minute and goes dark within ten; a button press or state change wakes it.
- Attention chirps on the device (and stops when the desktop mute field says so).
- A heartbeat with 6 entries + 6 sessions round-trips over BLE intact (HIL test).
- OTA on a real device ends with the app showing the *new* version as current, no residual "Update available".
