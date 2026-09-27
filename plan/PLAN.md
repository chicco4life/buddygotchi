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
| A7 | Two-stage brain | Superseded by A10 | [brain](evidence/2026-09-26-two-stage-brain/README.md), [evals](evidence/2026-09-26-eval-iteration/README.md) |
| A8 | Hero moments | Done, as C1 trimmed them; checks 4, 9, 10 and 13 | [evidence](evidence/2026-09-26-hero-moments/README.md) |
| C1 | Cut to 4 states and 3 animations | Done | [cut](evidence/2026-09-26-minimal-cut/README.md), [on the board](evidence/2026-09-26-e2e-hardening/README.md) |
| A9 | Modes: chatty, normal and calm | Superseded by A10: personalities replace modes | [evidence](evidence/2026-09-26-modes/README.md) |
| | Overnight pass (2026-09-27): reliability, behaviour and polish across the core, brain, firmware, face, Mac app and tools | Done. The final firmware `cf6d8ae` matches the simulator on the board in all 10 scenarios, `perf --motion` passes and `make e2e` passes; the new looks still need watching in motion (check 1) | [evidence](evidence/2026-09-27-overnight/) |
| A10 | Jev-only harness: typed events and transcript, a plain-text state, mood and personalities ([harness/](harness/HARNESS.md)) | Done; the evals pass against Jev; checks 12–17 are the owner's | [evidence](evidence/2026-09-27-jev-harness/README.md) |
| | Production and internal code split: what doesn't ship moves to `internal/`, `Package.swift` to the root ([internal/README.md](../internal/README.md)) | Done; the evals pass against Jev, 7/7 in all 3 runs | [evidence](evidence/2026-09-27-internal-split/README.md) |
| A11 | Seven moods, drawn from the mood SVGs: Jev picks the mood, and the device shows each state and reaction in it | In progress. Jev chooses among the seven moods with no minimum time between changes (evals 10/10 in all 3 runs); every `state` carries the mood; the device draws each look and the cheer as the mood's design, exactly as Chrome draws the SVGs. Still to do: the popover's face, and the board | [moods](evidence/2026-09-27-seven-moods/README.md), [faces](evidence/2026-09-27-mood-faces/README.md) |
| P1 | Port to ESP-IDF + LVGL | Later (§4) | |

## 2. Owner checks

What only a person can check: Bluetooth, sound and light, the
real screen and menu bar, and Jev with the owner's key. What Boop should
do is in [BEHAVIORS.md](BEHAVIORS.md) and [UX.md](UX.md). The app runs
the `boop` personality with the owner's Jev key unless a check says
otherwise. Anything
that's off becomes an open item (§3).

**The board and the app**

1. **Look at the board after the overnight changes.** They were checked
   on it by screenshot (every scenario matches the simulator pixel for
   pixel, [VERIFICATION.md](VERIFICATION.md) L2), but nobody has watched
   them move. Since then the face has become the mood designs (A11): watch
   each look and the cheer in a few moods (`internal/tools/boopctl play
   cheer --mood proud`, for one), the blink at each switch, and the tap's
   sway and heart. Say what you'd change.
2. **`make run`, or `make debug` to watch everything.** Within about 10 s
   the app connects to `Boop-XXXX` and the board leaves the no-app face.
   `make debug` also prints every hook, decision, device line and brain
   pass as it happens. If Bluetooth won't connect:
   `internal/tools/boopctl bridge`, then
   `.build/debug/Boop --link usb:/tmp/boop-bridge.sock`.
3. **If the agents aren't connected: Settings → Agents → Connect both,
   restart open sessions, then, from inside one agent session, run
   `internal/skills/doctor/doctor.sh`, `echo BOOP_DOCTOR_PING` and
   `internal/skills/doctor/doctor.sh --confirm`.** Both connected, the
   gen-2 `~/.boop` entries gone, and the doctor passes.
4. **Tap the screen lightly, then firmly; press BOOT; hold BOOT; then tap
   four times quickly and keep tapping.** Each touch or press is one
   wiggle, holding BOOT included, and a light touch counts once too
   (`make debug` prints one `device: input tap`), because a touch ends
   only after 50 ms without contact. The fourth quick tap also gets
   an annoyed mumble, and more tapping gets no second grumble within a
   minute ([BEHAVIORS.md](BEHAVIORS.md) §3.3).

**Agents**

5. **Make Claude ask permission for a quick shell command.** Within
   about 1 s Boop leans in with its amber sign, the amber light on the
   board's back glows, the strip says `claude · <project>`, and it chirps
   once. A tap only dips the face. Approving in the terminal blinks it back to working
   once the command has run (a long one stays amber until it ends,
   [ADAPTERS.md](ADAPTERS.md) §4); pressing Esc on the prompt instead
   leaves it amber until it goes idle about a minute later.
6. **Approvals in two sessions.** One chirp, and "+1" in the strip. Answer the
   first and the strip moves to the other, chirping if it's another agent
   or project.
7. **Two Claude subagents at once, one asking permission.** Boop stays
   amber while the other keeps running tools, until you answer.
8. **A Codex approval.** Amber about 2 s after Codex asks; one its
   automatic reviewer handles never lights up. This is Boop's first real
   Codex session (§3).
9. **A Claude task that runs past a minute.** The working face (the
   keyboard, in Boop's mood), then a cheer and a proud mumble,
   nearly always with a word.
10. **Ask Claude to run a failing test, then stop.** No cheer: Boop goes
    idle, then an annoyed mumble ("tests" or "ugh").
11. **Esc while Claude is between tool calls.** Within about a minute Boop
    goes idle, with no cheer or mumble; at once if a tool was running.

**Personalities and the brain**

12. **`make flash`, then `make run`, after push-to-talk's removal.** The
    popover has no Talk button, macOS no longer asks for the Microphone
    or Speech Recognition, and holding BOOT is just a wiggle
    ([ARCHITECTURE.md](ARCHITECTURE.md), decision log 2026-09-27).
13. **Paste Jev's key in Settings, then work normally for a while.** The
    Personality card loses its "Without a Jev API key" line. Routine
    turns go by quietly; a very long finish gets a proud mumble on top of
    the cheer ([harness/DECISIONS.md](harness/DECISIONS.md)).
14. **Let tests fail three times in a row, then pass.** On the third
    failure an annoyed mumble ("…again!" or "…tests!") and Boop turns
    grumpy (the `mood` file in `~/Library/Application Support/Boop/`);
    when they pass, a proud "…finally!" and Boop turns proud
    ([harness/EXAMPLE.md](harness/EXAMPLE.md)).
15. **`Boop --debug` (`make debug`) through a turn.** The terminal shows
    each event, the pass with Jev's whole state the first time and its
    answers, and what the actions did; `boop.log` has one `brain …` line
    per pass and none of the state ([harness/HARNESS.md](harness/HARNESS.md)
    §9).
16. **Settings → Personality: Chatter for a while, then Boop.** Chatter
    shows a "Chatter" chip, mumbles at nearly everything, including
    routine tool use, and chatters every 30–60 s while agents work. Boop
    is back to speaking up only when something stands out
    ([BEHAVIORS.md](BEHAVIORS.md) §6).
17. **`BOOP_JEV_KEY=… make eval`.** Every scenario passes in all three
    runs ([EVALS.md](EVALS.md)).

**The Mac app and the link**

18. **The popover and the menu-bar icon in light and dark, with an
    approval waiting.** The Warm Terminal look ([UX.md](UX.md) §6), with
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
    the no-app design with only the unplugged icon.

## 3. Open items

Known work that isn't a milestone yet, including drift found and not
fixed. Pick one up by writing it into its spec first.

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
- **Talking to Boop, quiet mode and memory are out.** Memory keeps only
  Boop's name and the day; they come back as events and actions
  ([FUTURE.md](FUTURE.md)).
- **Some of Voice's words can't be picked.** The brain offers eleven of
  the 40 ([harness/DECISIONS.md](harness/DECISIONS.md) §3); the rest are
  recorded on the device for nothing until the lists grow.
- **How fast a press shows on the board hasn't been measured since the
  dip.** A press now dips the face 2 px at once, so its first changed
  pixel comes on the press's own ms in the simulator
  (`test_the_redraw_cap_doesnt_delay_a_press`), where the old squish took
  20 ms; the board still has to draw and push it
  ([ARCHITECTURE.md](ARCHITECTURE.md) §9 has the 20 ms budget).
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
- **[harness/EXAMPLE.md](harness/EXAMPLE.md) predates the seven moods.**
  Its story stays happy through the second failure; with today's steering
  Boop turns determined there. It's still hand-written, with made-up
  odds; regenerate it from a real Jev run.
- **`swift build` rebuilds for no reason.** It alternates between a
  no-op (0.4 s) and a 6–9 s rebuild with nothing changed, so build
  timings are noisy until the cause is found.

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
