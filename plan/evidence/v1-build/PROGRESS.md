# v1 build progress

One entry per iteration, newest last. Each ends with the exact next step.

## 2026-09-26 00:55 — M0: Setup — Passed

- **Changed:** tag `gen2-final`, branch `v1-overnight`; gen-2 code deleted;
  new `app/` SwiftPM layout (BoopKit, Boop, boop-hook, boopdev, shim tests);
  new `firmware/` PlatformIO project (`cyd24`, `native`) with
  `firmware/tools/pio.sh`; `tools/boopctl` (ports, ping, state, send); new
  Makefile. Details in [M0/README.md](M0/README.md).
- **Checks:** make build, test, fw, fw-test, sim, tools and
  `boopctl ports` all passed.
- **Decisions:**
  - Reusable gen-2 files were deleted rather than parked; fetch them with
    `git show gen2-final:app/Boop/...` when the milestone needs them.
  - `app/Tests/GeneratedTestRunner.swift` is now git-ignored (regenerated
    by `make test`).
  - `.claude/skills/release` still describes the gen-2 packaging scripts,
    which are gone. Left alone; it's not part of v1's milestones.
  - `TODO.md` still lists gen-2 owner items; left for the owner.
- **Next step:** F1 board bring-up. Start with `firmware/src/board/`
  (LovyanGFX config for ST7789 on SPI2 and XPT2046 on SPI3, PWM backlight),
  the canvas push, the USB `dbg.*` channel at 921600, then the test pattern
  in `render/` so `native` can draw it too. Add `boopctl shot`, `diff`,
  `pattern`, `press`, `touch`, `clock` and `sim`, and `boopctl cam` for L3.

## 2026-09-26 00:58 — F1: Board bring-up — Passed

- **Changed:** LovyanGFX display and touch driver with a changed-rows DMA
  push; a pure C++ device core (`app/device.*`) with the whole debug channel,
  the clock and BOOT gestures, shared with `boop-sim` (stdin/stdout);
  the test pattern, 5×7 font and a placeholder face; the board HAL (LED,
  amp, battery, touch raw). boopctl gained `flash shot diff pattern press
  touch clock sim run cam`. Details in [F1/README.md](F1/README.md).
- **Checks:** fw-test 21/21; sim expects pass and 2 goldens reviewed; on the
  board: ping SHA matches, 160 KB free; `run` gives screenshots identical to
  the simulator's and every expect passes; webcam framing and pattern
  passed; LED red and blue seen on the webcam.
- **Decisions:**
  - USB serial runs at **460800**. The CH340 on macOS's driver can't do
    921600, for flashing or messages. Specs updated.
  - boopctl no longer touches DTR/RTS on open, which had rebooted the board.
  - NimBLE is out of `lib_deps` until F4 (it reserves 39 KB at boot).
  - Added `dbg.light` and `dbg.pattern` `fill` (VERIFICATION.md §3).
- **Board left on:** the test pattern, running F1 firmware `174d429931`.
- **Next step:** F2 renderer and simulator. Start with the "Warm Terminal"
  palette in `render/palette.h` and the face renderer in `render/`
  (eyes, lids, pupils, squash, mouth; eased blends ≤ 150 ms), replacing
  `drawPlaceholderFace`. Then add the screens (UX.md §2–3), a second font
  size, scenarios for every screen and state, `boopctl cam clip`, and
  `boopctl perf`, to check ≥ 25 fps during blends. If blends are too slow,
  try the SPI clock at 60–80 MHz (`board/display.h`).

## 2026-09-26 01:35 — F2: Renderer and simulator — Passed

- **Changed:** "Warm Terminal" palette with anti-aliasing ramps; an
  integer-only span/band rasterizer; Geist Mono fonts at 13 and 22 px
  (`tools/fontgen`); the pose-based face with eased, interruptible 150 ms
  blends; every animation in BEHAVIORS §7; all screens and the status
  strip; the device core now parses `state`/`moment` and picks the screen;
  `dbg.reset`; `boopctl perf` and `cam clip`. Details in
  [F2/README.md](F2/README.md).
- **Checks:** fw-test 42/42; 8 scenarios and 58 goldens, all reviewed; on the
  board, every expect passed and all 58 screenshots were identical to the
  simulator's; perf with motion gave a minimum of 44 fps and 157 KB heap;
  webcam framing passed, and the idle, needs-you and cheer clips were
  reviewed.
- **Decisions:** integer-only drawing (so the pixels match), Geist Mono
  (OFL), `dbg.reset` before every scenario, and webcam clips as live presets.
  All four are logged in ARCHITECTURE §11. 40 MHz SPI is enough.
- **Board left on:** F2 firmware `c47e775e53`. It shows the face, and goes
  to no app after 30 s without a Mac.
- **Next step:** F3 device behaviour. Start with a behaviour state machine
  in `firmware/src/app/` (pure C++, e.g. `behaviour.*`) that takes over from
  `Device::advance/resync/sourceAt`. Add idle life (blinks every 2–6 s,
  glances, from `rng_`), the nudge ladder's effects (amber LED, chirp
  flags, 3 light pulses at rung 3; visual only in focus), the gestures in
  UX.md §4 (tap face → wiggle + `input tap`; touch-and-hold the face → mood
  face; hold the strip → `focus`; feedback within 20 ms), the 10 s threads
  timeout, dimming (asleep, night, no app), hunger rumble, and mouth sync
  to `say`. Decide which moments may play over needs you (BEHAVIORS §1:
  attention wins). Then add goldens for every BEHAVIORS §3 row, and
  `boopctl soak`.

## 2026-09-26 02:19 — F3: Device behaviour — Passed

- **Changed:** a pure C++ behaviour state machine (`firmware/src/app/behaviour.*`).
  It covers base states, idle life, the needs-you ladder with its light and
  sound cues, moments shaped by mood, mouth sync, gestures with feedback on
  the press itself, the threads and stats timeout, dimming, and hunger. The
  device core now only parses, recognises gestures and draws. `dbg.state`
  gained `hushed`, `life`, `night`, `hungry` and `sfx`. New:
  `boopctl soak`, webcam presets `ladder`, `cheers` and `tap`, and scenarios
  `behaviour` and `life`. Details in [F3/README.md](F3/README.md).
- **Checks:** fw-test 55/55; the simulator ran 10 scenarios, and 22 new and
  8 changed goldens were reviewed; on the board, every expect passed and all
  80 screenshots were identical to the simulator's; perf gave a minimum of
  45 fps and 157 KB of heap; the 20-minute soak had no reset and 0 heap
  drift; webcam framing passed, and the ladder, cheers and tap clips were
  reviewed.
- **Decisions:** attention wins (only nod, listening, thinking, shrug and zip
  play over needs you); the device plays the nod on clearing, the fallback
  shrug, and the mood face, and sends a new `input` `feel`; `sfx` cues show
  in `dbg.state` before F5. All are in the ARCHITECTURE §11 log.
- **Board left on:** F3 firmware `a05f38af45`, showing the face.
- **Next step:** F4, Bluetooth on the device. Add NimBLE back to `lib_deps`
  (DEVICE.md §6) and a Nordic UART peripheral named `Boop-XXXX` (the last 4
  hex digits of the MAC) in `firmware/src/link/`. Feed RX through
  `app::LineReader` into `Device::handleLine(..., Link::kBle)`, with a
  `Device::setOut(Link::kBle, …)` writer that chunks to the MTU. Send
  `status` on connect and every 60 s (PROTOCOL §4), and release Classic BT
  memory. Keep the canvas allocated before BLE starts. Checks: L0
  reassembly tests (test_link already has some), `ping` shows advertising
  with heap_min ≥ 60 KB, and perf and soak re-run with BLE on. Don't use
  `bleak` or the Mac's Bluetooth; the real connection is checked in the
  morning.

## 2026-09-26 03:25 — F4: Bluetooth on the device — Passed

- **Changed:** a NimBLE-Arduino 2.x Nordic UART peripheral
  (`firmware/src/link/ble.*`) advertising as `Boop-54FE`, no security,
  Classic BT memory released, started after the canvas. Pure C++
  `app/packets.h`: a lock-free `ByteRing` hands received bytes from the
  Bluetooth task to the main loop's `LineReader` (same dispatch as USB), and
  a `PacketWriter` sends whole reply lines in MTU-sized notifications.
  `Device::connected/disconnected`, `status` on connect, every 60 s, and over
  USB when the Mac first speaks. `dbg.ping` gained `ble` and `name`. Details
  in [F4/README.md](F4/README.md).
- **Checks:** fw-test 61/61; sim 10 scenarios, 0 changed pictures; on the
  board with BLE advertising, every expect passed and all 80 screenshots were
  identical; ping `ble: adv`, heap 84 KB (target ≥ 60 KB); perf min 45 fps
  (unchanged), heap_min 82.7 KB; 20-minute soak clean, 0 heap drift. A real
  connection wasn't tried (no Mac Bluetooth from agents); it's for the
  morning.
- **Decisions:** USB `status` rule and `dbg.ping`'s `ble`/`name` are in the
  ARCHITECTURE §11 log; Bluetooth measured at about 75 KB (DEVICE.md §6).
- **Board left on:** F4 firmware `3707c8eb51`, advertising, on the face.
- **Next step:** A1, the app core: adapters, hook client, core rules. Read
  PLAN.md's A1 section and the specs it links (ADAPTERS.md, ARCHITECTURE.md,
  BEHAVIORS.md). The app's USB/BLE link must expect `status` lines (reply to
  the first one with a `state`) and ignore unknown types.

## 2026-09-26 03:20 — A1: App core — Passed

- **Changed:** a new Foundation-only `app/HookWire/` target, shared by
  `boop-hook` and the app. It holds the hook line (only the ADAPTERS §3
  fields), topic tags, and the socket send with a 50 ms timeout.
  `boop-hook` now writes one line to the Unix socket, never prints, always
  exits 0, and has a 1 s watchdog. `BoopKit/Adapters` gained `Adapter`
  (Claude and Codex tables, project names including worktrees),
  `HookServer` (the socket server) and `Replay`. `BoopKit/Core` gained
  `Core`, a pure state machine that returns effects. It covers sessions,
  "needs you" with the Codex grace period and safety net, screen priority
  and the `state` builder, XP, hunger, away, mood, chatter, quiet and focus,
  and trigger merging and gates. Also `Growth`, `Mood`, `StateSnapshot` and
  `LocalTime`. `boopdev replay` runs offline on a virtual clock, or with
  `--socket` through the real hook. There are synthetic Claude and Codex
  approval fixtures. Details in [A1/README.md](A1/README.md).
- **Checks:** `make test` 72/72 (three runs). Warm `boop-hook` runs with no
  app took at most 9 ms over 180 runs, all exit 0 and silent. The first
  launch after a rebuild took about 250 ms, twice; that's macOS's one-time
  check of a new binary, and the evidence records it. With the app
  listening, 23/23 lines arrived with no private text. Replay prints the
  expected snapshots (`ReplayTests`). No device checks, since A1 is
  Mac-only.
- **Decisions:** the HookWire target, the core as a pure state machine,
  leading-edge trigger merging, the late-Notification guard, stale-session
  rules, `state` fitting in 512 bytes (names cut to 23 bytes), days
  counting from 1, no XP for failures, and `lost` on the Growth line. All
  are in the ARCHITECTURE §11 log, with the specs updated.
- **Board:** untouched; still on F4 firmware `3707c8eb51`.
- **Next step:** A2: Memory, Voice and actions. Read PLAN.md's A2 section,
  ARCHITECTURE.md §4 (the file formats, including the new `lost:` on the
  Growth line), VOICE.md §3–7 and HARNESS.md §6 (the tool definitions).
  Build `BoopKit/Memory` (the three files, limits, atomic writes,
  `history/<date>/` snapshots, restore on a parse failure). It should
  consume the core's `.happened`, `.growth` and `.newDay` effects.
  `Core.init` takes `lastActiveDay` from short-term.md's Today date, so a
  restart doesn't replay the morning. Then build `BoopKit/Voice` and
  `BoopKit/Actions` (`say`, `face`, `quiet`, `note`, `remember`, `forget`,
  `temperament`, `moment`). `quiet` calls `Core.setQuiet`. Each action
  owns its tool definition and drops invalid input with a logged reason.

## 2026-09-26 03:40 — A2: Memory, Voice, actions — Passed

- **Changed:** new `BoopKit/Memory` (file formats, `MemoryStore` with
  limits, byte budgets, atomic writes, `history/<date>/` snapshots,
  rereading hand edits, restore), `BoopKit/Voice` (64 syllables, 40 words,
  dialects, feelings, tempo, the English check with word re-rolls and the
  safe hum), `BoopKit/Actions` (the eight actions, each with its
  `ToolDefinition` from `BoopKit/Harness/Tool.swift`), and `boopdev memory`
  and `boopdev voice`. Details in [A2/README.md](A2/README.md).
- **Checks:** `make test` 117/117, three runs. 10,000 Voice lines: 0 hits
  under the VOICE §7 rule, 4 safe hums. Every action's drops are logged
  with a reason. `make build` OK. No device checks (Mac-only).
- **Decisions:** doubled syllables skip the word list except common
  doubles; memory byte budgets (3,200 and 2,400); broken short-term keeps
  its date; `temperament`, `moment` and `remember` semantics; the 64-syllable
  set; `say` plays the feeling's face and respects quiet. All six are in
  the ARCHITECTURE §11 log, with the specs updated.
- **Board:** untouched; still on F4 firmware `3707c8eb51`.
- **Next step:** A3, the harness and brains. Read PLAN.md's A3 section and
  HARNESS.md in full. Build `BoopKit/Harness` around the existing
  `ToolDefinition`/`ToolCall` in `Harness/Tool.swift`: take
  `[Action]` from `Actions.all(...)` as the registry, run one call at a
  time (a newer trigger replaces a waiting one; `talk` cancels), build the
  prompt from `MemoryStore.steering`, `longTermText` and `shortTermText`
  (for `reflect`, use `reflectionText`), shape-check answers (at most 3
  calls, allowed tools only, against the definitions), dispatch with
  `action.run`, and log in debug mode. Brains: Apple via
  `DynamicGenerationSchema` (PLAN §1), rules-only from steering.md's
  Fallbacks table, and cloud as a disabled interface. Fixtures: 50+
  triggers plus sample memory in `app/Tests/Fixtures/{triggers,memory}`.

## 2026-09-26 03:59 — A3: Harness and brains — In progress

- **Changed:** new `BoopKit/Harness/{Brain,Prompt,Harness}.swift`: the
  `Brain` protocol and the one answer format (`{"calls":[…]}`), the shape
  check (`Answer.check`, sharing `ToolDefinition.check` with the actions),
  the prompt builder with its budgets, and the `Harness` (one call at a
  time on a `home` queue, a newer trigger replaces the waiting one, `talk`
  cancels, deadline race, JSONL debug log). New `BoopKit/Brains/`:
  `AppleBrain` (a runtime `DynamicGenerationSchema` with a leading `react`
  choice), `RulesBrain` (reads the Fallbacks table from the prompt),
  `CloudBrain` (disabled) and `Brains.make`. `MemoryStore.promptMemory(for:)`.
  `boopdev brain`. 52 fixture triggers in `app/Tests/Fixtures/triggers/`
  and sample memory in `app/Tests/Fixtures/memory/`. `Tests/HarnessTests.swift`
  (18 tests: shape check, order, offered tools, more than 3 calls, errors
  and lateness, replace, talk cancel, prompt layout, budgets, fixtures,
  debug log; rules brain rows; cloud disabled; Apple schema builds).
- **Spec changes** (ARCHITECTURE §11, four rows): `event` no longer offers
  `note`; `forget` picks from existing lines (its definition is rebuilt per
  call); one answer format with Apple's `react`-first schema; the rules
  brain reads its table from the prompt. steering.md: tighter Notes and
  Reflection wording. HARNESS §3/§5/§6/§7 and VERIFICATION §2 updated.
- **Checks:** `make test` 135/135, three runs. L5 with the rules brain:
  52/52 valid, 0 drops, PASS. L5 with Apple's model (`apple:27.0`),
  `plan/evidence/v1-build/A3/l5-apple-run1.txt`: 52/52 valid shape, 1/87
  calls dropped (1.1%, a note with `=`), silence 2/52, p95 event 1.9 s,
  tap 1.8 s, talk 2.2 s, reflect 2.2 s — the numbers pass.
- **The sample review does NOT pass yet**, so A3 stays In progress:
  1. **Reflection is harmful:** all 4 reflect runs `forget` "Ships on
     Fridays." (a true fact) and `remember` "flaky tests, third attempt"
     (about the agent, not the person).
  2. **Filler word:** `say` adds `word: tests` to greetings, praise and
     starts ("good job today" → curious + tests). It should usually have no
     word. Likely because `tests` is the first vocabulary entry.
  3. **Rarely silent** (2/52); quick finishes and starts almost always get
     a face and a mumble. Long finishes get smug/curious, never
     `proud`/`finally`.
  4. Minor: "shut up for an hour" → `quiet(30)` (example says 60); "keep it
     down for fifteen minutes" → no quiet at all.
  Good: failures → side_eye; hungry taps → `hopeful`/`food`; "shut up",
  "be quiet", "stop talking" → sulky + quiet; "remember I ship on
  Fridays" → note; never nagging.
- **Tried already:** a flat "slots" schema (one optional property per
  tool) filled every slot (3–4 calls per answer, one over the limit);
  dropped. A plain calls list without `react` never stayed silent.
- **Board:** untouched; still on F4 firmware `3707c8eb51`.
- **Next step:** fix the review findings, then rerun
  `app/.build/debug/boopdev brain --brain apple --print` (about 90 s)
  and review again. Ideas in order: (1) reflection: don't offer `forget`
  unless yesterday's notes say something the person corrected, or make
  the Apple schema's reflect `react` choice explicit ("nothing to keep" /
  "keep something"), and add a reflection example to steering.md showing
  `remember` of something the person said and no `forget`; (2) put
  `word` behind its own choice in the Apple schema (e.g. the say object's
  `word` offered with a leading "none" option that maps to leaving it out)
  so the first enum entry isn't the default; (3) add steering examples
  for a turn started (no tool calls) and a long finish. If the review
  passes, write `A3/README.md`, set A3 Passed, and commit
  `A3: Harness and brains — …`. Don't spend more than ~45 min on tuning;
  if the reflection problem persists, Block with the evidence.

## 2026-09-26 04:18 — A3: Harness and brains — Blocked

- **Changed:** Apple's schema starts every choice with `none`, which drops
  an optional argument, or drops the call when the choice is required. It
  uses `permissiveContentTransformations` guardrails at temperature 0.5.
  v1 reflection no longer offers `forget`. `moment` refuses a retelling of
  an earlier moment. steering.md: new examples (a turn started gets
  nothing, praise, "hello boop", "you're the best", tapped late at night,
  an ordinary reflection day gets nothing), stricter Notes rules, and
  "never `remember` agent news". The sample short-term notes are now
  facts the person told Boop. HARNESS §5/§6/§7, ARCHITECTURE §4.2/§5 and
  three decision-log rows were updated.
- **Checks:** `make test` 135/135. L5 rules: PASS. L5 Apple
  (`A3/l5-apple-run2.txt`): valid shape 50/52 (2 guardrail refusals),
  2/86 calls dropped, all p95 values under their deadlines, so **FAIL** on
  the 100% valid-shape check. The review still fails: talk notes praise and
  greetings, 18/52 answers mumble `tests`, and only 4/50 were silent.
  Reflection no longer deletes facts and remembers the right one. Six more
  variants were tried; see `A3/README.md`.
- **Decision:** after about 45 min of tuning in this iteration (plus the
  last one's), A3 is **Blocked** per PLAN §3.6. The fix probably needs a
  spec call from the owner: the core deciding when the brain speaks, and
  `note` gated to fact-like words.
- **Board:** untouched; still on F4 firmware `3707c8eb51`.
- **Next step:** start **A4** (device link, app shell, push-to-talk,
  installer). Read PLAN.md §4 A4 and the specs it links. The harness is
  usable; default the app's brain setting to Apple as specced, and use
  `--brain rules` for the headless USB checks in A4/J1 so they're
  deterministic.

## 2026-09-26 04:42 — A4: Device link, app shell, push-to-talk, installer — Passed

- **Changed:** new `BoopKit/DeviceLink` (framer, messages, `DeviceLink`,
  `USBTransport`, `BLETransport`), `BoopKit/App` (`Runtime` wiring
  everything on one queue, `AppSettings`, `InstanceLock`),
  `BoopKit/Install/HookInstaller`. The `Boop` target is now the real app:
  `--headless`, the menu bar with popover, settings and setup, push-to-talk
  (Speech, on-device), Keychain, an embedded `Info.plist` and a bundled
  `steering.md`. `boopctl bridge` (and other boopctl commands go through a
  running bridge), `boopdev talk` and `boopdev hooks`, and a rewritten
  doctor. Specs: ADAPTERS §5–6, VERIFICATION §2, seven decision-log rows,
  the morning checklist (steps 5–7), CLAUDE.md/AGENTS.md self-diagnosis.
- **Checks:** `make build` pass; `make test` 160/160. Live over USB with
  the bridge and a headless app: hooks → board "needs you" → nod; hold,
  tap, `boopdev talk "shut up"` → quiet 30 on the board; SIGTERM exits 0
  and removes both sockets. Doctor `--headless` on a temp HOME: 7/7. See
  `A4/README.md`. Not run: the menu-bar app and Bluetooth (owner, morning).
- **Found:** the owner's `~/.claude` and `~/.codex` still hold only gen-2
  hook entries (read-only check; left alone).
- **Board:** untouched firmware (F4, `3707c8eb51`); no bridge or app left
  running.
- **Next step:** start **J1** (end to end over USB). Read PLAN.md §4 J1 and
  VERIFICATION.md L4. Build the fixtures (Claude session with topics, a
  permission, a long Stop, a StopFailure; Codex requests resolved within
  2 s and after 10 s), then a `make e2e` script: `boopctl bridge --socket
  /tmp/boop-e2e/usb.sock`, `Boop --headless --state-dir /tmp/boop-e2e/state
  --link usb:… --brain rules`, `boopdev replay … --socket …`, and `boopctl
  expect` at each checkpoint. Latency: have the app log when each hook's
  `state` goes out (or have `boopdev replay` poll `dbg.state`) to get
  hook-to-device p95 < 200 ms; `boop-hook`'s own launch is ~70 ms of that.
  Long waits in fixtures (`{"wait_ms":400000}`) need a virtual clock or
  shorter waits: the headless app runs on the real clock.

## 2026-09-26 05:10 — J1: End to end over USB — Passed

- **Changed:** `boopctl e2e` / `make e2e` (bridge + headless app +
  fixtures through the real `boop-hook`, checkpoints on `dbg.state`,
  latency, memory, privacy and brain-ordering checks, `--clip` for the
  webcam). Fixtures in `app/Tests/Fixtures/hooks/e2e/`. Firmware:
  `dbg.state` `rx` counts (flashed). Headless: `{"dev":"advance"}` clock
  jump, `--trace`. **Bug fixed:** the brain's `face` replaced the rules'
  cheer/oops within 7 ms; brain moments now wait for the rule moment and
  the core's follow-ups. Specs: VERIFICATION §2/§3/L4, BEHAVIORS §3,
  ARCHITECTURE §3.2 + three decision-log rows.
- **Checks:** `make test` 163/163; `make fw-test` 61/61. L4 with the rules
  brain and with Apple's: every checkpoint passes, p95 91/92 ms, XP 8 as
  specified, no private text anywhere, no brain moment early or cut off.
  L3: framing passed; a 10 s clip of a Claude session through the
  pipeline reviewed and passing. See `J1/README.md`.
- **Board:** firmware from this commit (F4 + `rx`), no bridge or app left
  running.
- **Next step:** start **F5** (voice on the device). Read PLAN.md §4 F5,
  VOICE.md and DEVICE.md (DAC, amp). Build `tools/voicegen` (macOS `say` →
  `afconvert` → pitch/normalise → 8-bit 11.025 kHz → `firmware/assets/voice.h`),
  then the player (amp on, continuous DAC at 22.05 kHz, resampling for
  pitch and tempo) with resampler tests on `native`, and check the audio
  timeline in `dbg.state` against `say` over USB. Keep the app slot at least
  15% free (now 43% used).

## 2026-09-26 05:35 — F5: Voice on the device — Passed

- **Changed:** `tools/voicegen` (Italian `say` for syllables, English for
  words, synthesised hums; 226 KB, reproducible) → `firmware/assets/voice.h`.
  `firmware/src/voice/player` (resampling to 22.05 kHz, beats, tune,
  jitter within pairs of beats, volume, chirp and jingle cues).
  `firmware/src/board/audio` (a core-0 task streaming the continuous DAC,
  with the amp gated per line). The device core turns `moment.say` into a
  line, keeps silent for needs you, quiet, focus and mute, and hushes on a
  new moment. `dbg.state` `audio.out`, `dbg.ping` `voice`, and
  `boopctl voice`. Specs: DEVICE §4–6, VOICE §8, VERIFICATION §2–3, three
  decision-log rows, and morning steps 16–17.
- **Found:** ESP-IDF's sync DAC writes time out for good once the DMA runs
  dry. The DAC now streams without a break (silence when idle).
- **Checks:** `make fw-test` 74/74; `make test` 163/163. L2 `boopctl
  voice` 32/32 lines (worst DAC timing error 0.4%, limit 10%), and mute is
  silent. The app slot is 55.7% used. `boopctl sim` and `boopctl run`: 10
  scenarios, 0 differences. perf fps min 44; 5-minute soak ok, 0 DAC
  errors. Not heard: no speaker. No webcam clip (nothing on screen changed).
- **Board:** F5 firmware (reflashed from the commit), on the idle face, no
  bridge or app running.
- **Next step:** start **J2** (soak and polish). Read PLAN.md §4 J2. Run a
  30-minute soak with replayed traffic *and the Apple brain*: probably
  `boopctl bridge` + `Boop --headless --brain apple --link usb:…`, with
  `boopdev replay` fixtures on a loop (see `tools/boopctl_lib/e2e.py` for
  the wiring), sampling `dbg.ping`/`dbg.state` for resets, heap drift,
  stuck states and `audio.out.errors`. Confirm every test is green and
  every golden reviewed, and rewrite `README.md` for the v1 product and
  commands (`make` targets, `boopctl` including `voice`, `voicegen`).

## 2026-09-26 05:36 — Owner decisions: A3 reopened, webcam off

The owner read the A3 blocker (`A3/README.md`) and decided:

- **Over-speaking is the one problem to fix now, and the harness fixes
  it.** Don't rely on the model to choose silence. The harness blocks brain
  speech past a limit, in code, so Boop stays quiet most of the time
  whatever the model answers. Keep the harness generic: the limits are
  plain data (for example a per-trigger or per-tool limit in HARNESS.md
  §5), not Minion logic. Prefer not offering `say` once its limit is
  reached over dropping it afterwards, since a small model can't pick a
  tool it isn't offered. Choose the values yourself (for example, on
  `event`, brain speech at most once every 10 minutes and never on a turn
  start), put them in the spec, and add a decision-log row.
- **The other findings are quality issues for later tuning, not
  blockers:** `note` on praise and greetings, the `tests` filler word, a
  `moment` every day, and Apple's guardrail refusals. List them in
  `A3/README.md` under "Known issues for later tuning". Treat a guardrail
  refusal as a silent drop (Boop keeps the rule reaction, as it does now):
  change L5 to measure valid shape over the answers the model gave and to
  report refusals separately (VERIFICATION.md L5, plus a decision-log row).
- **Webcam off for the rest of this run.** The owner is using the laptop
  and has withdrawn the webcam authorisation. Don't open the camera at
  all, not even for the framing check. Skip every L3 check, say so in each
  PROGRESS.md entry and in the J3 report, and never count a skipped L3 as
  passed. LOOP.md §4 and PLAN.md §3 now say the same.
- **Next step:** A3 is In progress again and comes before F5 in PLAN.md
  §4's order, so do it first. Build the speech limit in the harness, with
  unit tests on a virtual clock (a fake brain that always speaks, and the
  limit holds). Update HARNESS.md §3 step 2, which says one call at a time
  is the harness's only scheduling rule, and §5. Rerun L5 with Apple's
  model and review the sample as L5 says, judging silence on what Boop
  would actually say after the limit; the deferred issues above are noted
  but don't fail it. If it passes, write `A3/README.md`, set A3 Passed and
  commit `A3: Harness and brains — …`. Then go back to F5 where the entry
  before this one left off.

## 2026-09-26 05:50 — A3: Harness and brains — Passed (owner's ruling)

- **Changed:** the harness limits brain speech in code, as plain data per
  trigger kind (`Trigger.Kind.limits`, `ToolLimit`, `ToolLimits`): `say` on
  `event` at most once every 10 min and never on a turn start, on `tap`
  once every 5 min, on the triggers' own clock. A tool past its limit isn't
  offered; a second `say` in one answer is dropped. Guardrail refusals are
  `BrainError.refused` and counted apart. `boopdev brain` spaces triggers
  3 min apart under one limit history (`--gap-min`) and reports refusals,
  valid shape over answers given, and speech per trigger. Steering: one
  talk example for an indirect quiet request (bundled copy in sync).
  Specs: HARNESS §3, §5, §6, §7; VERIFICATION §2, L0, L5; two decision-log
  rows.
- **Checks:** `make test` 166/166; `make e2e` PASS (rules brain, board
  over USB). L5 rules 52/52 PASS. L5 Apple, 3 runs: 2 refusals each, 50/50
  valid shape each, no speech on turn starts, events spoke 5/24 and taps
  4/8. Action drops 5.5% (run 3, before the steering example), 2.7% (run
  4) and 6.8% (run 5), against a 5% line. **The drop check failed in 2 of
  3 runs.** Every drop over the line is in reflection: `moment` retellings
  (the deferred "moment every day") and `remember("jetpack = payments")`
  hitting memory's code check. Marked Passed under the owner's ruling that
  the deferred issues don't fail A3; `A3/README.md` says this plainly and
  lists the known issues. L3 skipped (webcam withdrawn; nothing on screen
  changed).
- **Decided:** kept the 5% line and reported the failures, rather than
  changing the check to leave out reflection.
- **Board:** firmware untouched (F5), on the idle face; no bridge or app
  running.
- **Next step:** start **J2** (soak and polish). Read PLAN.md §4 J2. Run a
  30-minute soak with replayed traffic *and the Apple brain*: `boopctl
  bridge` + `Boop --headless --brain apple --link usb:…`, with `boopdev
  replay` fixtures on a loop (see `tools/boopctl_lib/e2e.py` for the
  wiring), sampling `dbg.ping`/`dbg.state` for resets, heap drift, stuck
  states and `audio.out.errors`. Confirm every test is green and every
  golden reviewed, and rewrite `README.md` for the v1 product and commands
  (`make` targets, `boopctl` including `voice`, `voicegen`, `boopdev brain
  --gap-min`). Webcam stays off: skip L3 and say so.
