# Boop: plan

Updated 2026-09-27. Where Boop stands: each milestone's status (§1), the
checks only the owner can do (§2), the open items (§3) and the later port
to ESP-IDF + LVGL (§4). How each milestone was planned and closed is in
the [v1 build plan](../archived/plan-v1-build/PLAN.md), and the specs are
listed in [README.md](README.md).

## 1. Status

Every v1 milestone is done, apart from what only the owner can check
(§2). [VERIFICATION.md](VERIFICATION.md) defines the checks, and each
milestone's evidence says which ones ran.

| # | Milestone | Status | Evidence |
| --- | --- | --- | --- |
| M0 | Setup | Done | [M0](evidence/v1-build/M0/README.md) |
| F1 | Board bring-up | Done | [F1](evidence/v1-build/F1/README.md) |
| F2 | Renderer and simulator | Done | [F2](evidence/v1-build/F2/README.md) |
| F3 | Device behaviour | Done | [F3](evidence/v1-build/F3/README.md) |
| F4 | Bluetooth on the device | Done | [F4](evidence/v1-build/F4/README.md) |
| A1 | App core: adapters, hook client, core rules | Done | [A1](evidence/v1-build/A1/README.md) |
| A2 | Memory, Voice and actions | Done | [A2](evidence/v1-build/A2/README.md) |
| A3 | Harness and brains | Done; A7 replaced its brains | [A3](evidence/v1-build/A3/README.md) |
| A4 | Device link, app shell, push-to-talk, installer | Done | [A4](evidence/v1-build/A4/README.md) |
| J1 | End to end over USB | Done | [J1](evidence/v1-build/J1/README.md) |
| F5 | Voice on the device | Done, heard on a speaker | [F5](evidence/v1-build/F5/README.md), [speaker](evidence/2026-09-26-speaker/README.md) |
| J2 | Soak and polish | Done | [J2](evidence/v1-build/J2/README.md) |
| J3 | Handoff | Done; its [report](evidence/v1-build/REPORT.md) is the build's summary as it ended | [J3](evidence/v1-build/J3/README.md) |
| F6 | Landscape screen and cuter eyes | Done; C1's pixel face replaced the eyes | [F6](evidence/v1-build/F6/README.md), [gen-2 look](evidence/2026-09-26-gen2-look/README.md) |
| A5 | Mac app look and flow | Done; the owner still has to check the look (check 18) | [A5](evidence/v1-build/A5/README.md) |
| A6 | Brain conversation | Superseded by A7 | [evidence](evidence/2026-09-26-brain-conversation/README.md) |
| A7 | Two-stage brain | Done; checks 13–15 | [brain](evidence/2026-09-26-two-stage-brain/README.md), [evals](evidence/2026-09-26-eval-iteration/README.md) |
| A8 | Hero moments | Done, as C1 trimmed them; checks 4, 9, 10 and 13 | [evidence](evidence/2026-09-26-hero-moments/README.md) |
| C1 | Cut to 4 states and 3 animations | Done | [cut](evidence/2026-09-26-minimal-cut/README.md), [on the board](evidence/2026-09-26-e2e-hardening/README.md) |
| A9 | Modes: chatty, normal and calm | Done; checks 16 and 17 | [evidence](evidence/2026-09-26-modes/README.md) |
| | Overnight pass (2026-09-27): reliability, behaviour and polish across the core, brain, firmware, face, Mac app and tools | Done. The final firmware `cf6d8ae` matches the simulator on the board in all 10 scenarios, `perf --motion` passes and `make e2e` passes; the new looks still need watching in motion (check 1) | [evidence](evidence/2026-09-27-overnight/) |
| A10 | Jev-only harness: typed events and transcript, a plain-text state, mood, `[PENDING]` ([HARNESS.md](HARNESS.md)) | Spec written; code in progress (§3, "Harness rework") | |
| P1 | Port to ESP-IDF + LVGL | Later (§4) | |

## 2. Owner checks

What only a person can check: Bluetooth, the mic, sound and light, the
real screen and menu bar, and Jev with the owner's key. What Boop should
do is in [BEHAVIORS.md](BEHAVIORS.md) and [UX.md](UX.md). The app is in
normal mode with no Jev key unless a check says otherwise. Anything
that's off becomes an open item (§3).

**The board and the app**

1. **Look at the board after the overnight changes.** They were checked
   on it by screenshot (every scenario matches the simulator pixel for
   pixel, [VERIFICATION.md](VERIFICATION.md) L2), but nobody has watched
   them move: the face moving as one sprite, the one-block breathing bob,
   the working strain and sweat drop, the cheer's landing squash and
   beating heart, and the listening "ooh". Say what you'd change.
2. **`make run`, or `make debug` to watch everything.** Within about 10 s
   the app connects to `Boop-XXXX` and the board leaves the no-app face.
   `make debug` also prints every hook, decision, device line and brain
   pass as it happens. If Bluetooth won't connect: `tools/boopctl bridge`,
   then `app/.build/debug/Boop --link usb:/tmp/boop-bridge.sock`.
3. **If the agents aren't connected: Settings → Agents → Connect both,
   restart open sessions, then, from inside one agent session, run
   `skills/doctor/doctor.sh`, `echo BOOP_DOCTOR_PING` and
   `skills/doctor/doctor.sh --confirm`.** Both connected, the gen-2
   `~/.boop` entries gone, and the doctor passes.
4. **Tap the screen lightly, then firmly; press BOOT; hold BOOT; then tap
   four times quickly and keep tapping.** Each touch or press is one
   wiggle, and a light touch counts once too (`make debug` prints one
   `device: input tap`), because a touch ends only after 50 ms without
   contact. Holding BOOT shows `listening`. The fourth quick tap also gets
   an annoyed mumble, and more tapping gets no second grumble within a
   minute ([BEHAVIORS.md](BEHAVIORS.md) §3.3).

**Agents**

5. **Make Claude ask permission for a quick shell command.** Within
   about 1 s Boop leans in, the amber light on the board's back glows,
   the bubble says `claude · <project>`, and it chirps once. A tap only
   squashes the face. Approving in the terminal blends it back to working
   once the command has run (a long one stays amber until it ends,
   [ADAPTERS.md](ADAPTERS.md) §4); pressing Esc on the prompt instead
   leaves it amber until it goes idle about a minute later.
6. **Approvals in two sessions.** One chirp, and "+1 more". Answer the
   first and the bubble moves to the other, chirping if it's another agent
   or project.
7. **Two Claude subagents at once, one asking permission.** Boop stays
   amber while the other keeps running tools, until you answer.
8. **A Codex approval.** Amber about 2 s after Codex asks; one its
   automatic reviewer handles never lights up. This is Boop's first real
   Codex session (§3).
9. **A Claude task that runs past a minute.** The working face (a sweat
   drop, a strain every few seconds), then a cheer and a proud mumble,
   nearly always with a word.
10. **Ask Claude to run a failing test, then stop.** No cheer: Boop goes
    idle, then an annoyed mumble ("tests" or "ugh").
11. **Esc while Claude is between tool calls.** Within about a minute Boop
    goes idle, with no cheer or mumble; at once if a tool was running.

**Talking to Boop**

12. **Hold BOOT: "be quiet for fifteen minutes".** The quiet icon on the
    strip, "Quiet · 15 min" in the popover, and no mumbles until it ends.
    An approval still chirps. Then hold BOOT: "you can talk again". The
    icon goes and Boop mumbles happily.
13. **Hold BOOT and snap "shut up"; then yell something neutral.** A sad
    mumble each time, and no quiet. If your normal voice counts as a yell,
    or a real yell doesn't, tune the threshold
    ([BEHAVIORS.md](BEHAVIORS.md) §3.3).
14. **Hold BOOT: "remember I ship on Fridays", then "remember the demo is
    on Thursday".** A happy mumble each time. The first shows in Settings
    under What Boop remembers, the second in today's notes
    (`~/Library/Application Support/Boop/short-term.md`).
15. **Click Talk in the popover, say "good job", click Send; then Talk and
    say nothing.** macOS asks for Speech Recognition and the Microphone
    the first time. While the mic is on, the menu-bar eyes turn red with a
    bigger dot, the popover says "Listening…" over a red Send, macOS shows
    its mic indicator, and the device shows `listening`, with no chatter
    cutting in. After Send, a proud mumble within a few seconds; left
    alone, everything goes back after 30 s.
16. **Settings → Mode: Chatty for a while, then Calm.** Chatty mumbles
    when an agent starts, with every cheer and every minute or so, and
    shows a "Chatty" chip. Calm has no cheer under a minute, no chatter
    and no grumble at a poke streak, and shows a "Calm" chip; needs you
    and failed turns still come through. Each takes effect at once
    ([BEHAVIORS.md](BEHAVIORS.md) §6).
17. **`BOOP_JEV_KEY=… make eval REAL=1`, then paste the key in Settings
    under Normal.** The evals pass with Jev deciding normal mode
    ([EVALS.md](EVALS.md)), and the app decides with Jev from the next
    input.

**The Mac app and the link**

18. **The popover and the menu-bar icon in light and dark, with an
    approval waiting.** The Warm Terminal look ([UX.md](UX.md) §7), with
    the needs-you icon's deeper amber clear on a light menu bar. In the
    active popover, setup's switches are sage when on and the volume
    slider fills in ink, which `Boop --snapshots` can't show.
19. **Over Bluetooth, an approval arriving as a turn finishes (two
    sessions); separately, BOOT pressed again within a second of letting
    go.** The screen always matches the popover, and the second press is
    heard ([evidence](evidence/2026-09-26-e2e-hardening/README.md)).
20. **Settings → Device → Reconnect; then `kill -9` the app and `make run`
    again; then quit it and wait 30 s.** Both reconnects find the board
    within a couple of seconds, the second by taking over the link macOS
    kept ([PROTOCOL.md](PROTOCOL.md) §2). After quitting, the board shows
    the asleep look with only the unplugged icon.

## 3. Open items

Known work that isn't a milestone yet, including drift found and not
fixed. Pick one up by writing it into its spec first.

- **Harness rework (A10).** [HARNESS.md](HARNESS.md) describes the
  Jev-only harness, and the code still runs the two-stage one. Until it
  lands, these still describe the old harness and move with the code:
  `plan/steering.md` (splits into `plan/steering/`), the `steering.md`
  rule in CLAUDE.md, [ARCHITECTURE.md](ARCHITECTURE.md) §3.2–3.3 and §4
  (bursts, the stages, memory writes), [BEHAVIORS.md](BEHAVIORS.md) §3.3
  and §6 (talk, modes), [VOICE.md](VOICE.md) §6 (who picks the word),
  [ADAPTERS.md](ADAPTERS.md) §2–3 (the extra hook fields, the workspace,
  Codex's `Interrupt`), [EVALS.md](EVALS.md) and
  [UX.md](UX.md) §7 (Mode becomes Personality). Talk and memory writes
  come back after it.

- **Release.** There's no signing, notarisation, app icon or release
  pipeline yet. Gen-2's list is in
  [archived/docs/TODO-gen2.md](../archived/docs/TODO-gen2.md).
- **The landing page sells gen-2.** [Its copy](../landing/src/lib/copy.ts)
  leads with "Approve with a pet" and a press to approve or deny, which
  [VISION.md](VISION.md)'s promises rule out. It lists Cursor and VS
  Code, and its help describes gen-2's approval mode, port 21321 and
  `~/.boop`.
- **No real Codex session.** Only a Codex `SessionStart` has been
  recorded; the approvals and tool calls in the fixtures are hand-written,
  so the shell tool's name and its argv `command` are guesses. What
  `PostToolUse` reports after a failed command hasn't been seen either, so
  a Codex turn never fails ([ADAPTERS.md](ADAPTERS.md) §3). One recorded
  session with an approval and a failing test run would settle both.
- **A denied subagent can keep "needs you" until the main turn ends.**
  A subagent you deny carries on, and if it ends without another tool
  call, Claude sends only `SubagentStop`, which Boop doesn't hook. So its
  request stays until the main agent's `Stop`, or the safety net
  ([ADAPTERS.md](ADAPTERS.md) §4). Hooking `SubagentStop` and letting it
  answer only that subagent's request would clear it; it mustn't make an
  idle session working.
- **A failed test turn's word is on a knife-edge.** Apple's writer picks
  the right source (the failed topic) but flips between "tests" and "ugh"
  with small, unrelated prompt changes; evals 06 and 13 accept both.
  Supplying the topic word when that source is picked would make it
  "tests" every time
  ([evidence](evidence/2026-09-27-overnight/brain/README.md)).
- **Complaints and sarcasm.** "ugh, the tests are flaky again" is curious
  in the if-else tables but annoyed in `steering.md`'s example, and
  "great, the build broke again" is praise. Decide whether a complaint
  row, before praise, belongs in the phrase table
  ([HARNESS.md](HARNESS.md) §6).
- **A waiting input's deadline starts late.** An agent input held behind a
  pass for what you said gets its 5 s only when its own pass starts, so
  its mumble can land well after the event ([HARNESS.md](HARNESS.md) §3).
- **Temperament and Moments never change.** Nothing writes them since the
  new day's reflection was parked. Decide whether they stay, go, or get a
  writer ([FUTURE.md](FUTURE.md), "The new day's reflection").
- **Memory's text checks are literal.** A duplicate has to be the same
  text, so "landing launches on Monday" is kept beside "landing launches
  Monday", and any `=` is refused as code ("jetpack = payments").
- **A press takes about 20 ms to show, right at the budget**
  ([ARCHITECTURE.md](ARCHITECTURE.md) §9). The squish eases in over 60 ms,
  a block at a time, so its first changed pixel comes 20 ms after a BOOT
  press (`test_the_redraw_cap_doesnt_delay_a_press`), and the board still
  has to draw and push it. A squish with a bigger first step would meet
  it.
- **Shear during fast moves.** On the webcam the face shears diagonally as
  it moves fast. It's either the panel (no tear-effect sync, and in
  landscape its scan crosses the rows the firmware writes) or the camera's
  rolling shutter. If it shows to the eye, try SPI at 80 MHz (40 now) or
  pushing rows in the panel's order
  ([evidence](evidence/2026-09-26-e2e-hardening/README.md)).
- **USB can lose a line from the board.** The CH340 drops the odd byte
  (two debug replies and 23 characters in a 31-minute soak), and lines
  have no sequence numbers, so a lost tap is gone. Bluetooth doesn't go
  through it. Number the board's lines, or drop to 230400 baud.
- **About 14 KB of heap headroom.** The minimum free heap
  ([DEVICE.md](DEVICE.md) §6) is only just over the 60 KB target, so
  anything that adds RAM needs measuring.
- **A freshly built `boop-hook` is slow once:** about 250 ms on its first
  launch while macOS checks it, then a few milliseconds.
- **`swift build` rebuilds for no reason.** In `app/` it alternates
  between a no-op (0.4 s) and a 6–9 s rebuild with nothing changed, so
  build timings are noisy until the cause is found.

## 4. P1: Port to ESP-IDF + LVGL (later)

**Gate:** only after the owner has run §2 and confirmed v1 works. Then
port everything, tools and checks included:

- **Project:** ESP-IDF, through PlatformIO (`framework = espidf`) or
  `idf.py`, with `esp_lcd` for the ST7789 and `esp_lcd_touch_xpt2046` on
  separate SPI hosts, as today.
- **Drawing:** LVGL 9 through `esp_lvgl_port`. Boop's canvas renderer
  stays, shown through an LVGL canvas.
- **The rest:** raw NimBLE Nordic UART, the continuous DAC, NVS, and the
  same USB debug channel with `dbg.shot`. `boopctl`, the scenarios, the
  goldens and the webcam checks stay as they are, because the protocol
  doesn't change.

**Done when** the whole L0–L4 suite passes against the ESP-IDF build
unchanged, screenshots match the current goldens or the differences are
reviewed, and performance is the same or better, with the budgets in
[DEVICE.md](DEVICE.md) updated. After P1, Secure Boot v2, flash
encryption and Bluetooth bonding get a milestone of their own.
