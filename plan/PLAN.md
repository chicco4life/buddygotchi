# Boop: plan

Updated 2026-09-27. Where Boop stands: each milestone's status (§1), the
checks only the owner can do (§2), the open items (§3) and the later port
to ESP-IDF + LVGL (§4). How each milestone was planned and closed is in
the [v1 build plan](../archived/plan-v1-build/PLAN.md), and the specs are
listed in [README.md](README.md).

## 1. Status

Every v1 milestone is done except A11, which waits on watching the faces
on the board, and apart from what only the owner can check (§2).
[VERIFICATION.md](VERIFICATION.md) defines the checks, and each
milestone's evidence says which ones ran.

| # | Milestone | Status | Evidence |
| --- | --- | --- | --- |
| | The v1 build (M0–J3), the early looks and brains (F5, F6, A6, A7, A9) and the cut to 4 states (C1) | Done or superseded; their rows are in the [archive](../archived/plan-v1-build/status.md) | |
| A5 | Mac app look and flow | Done; the owner still has to check the look (check 17) | [A5](evidence/v1-build/A5/README.md) |
| A8 | Hero moments | Done, as C1 trimmed them; checks 4, 9, 10 and 12 | [evidence](evidence/2026-09-26-hero-moments/README.md) |
| | Overnight pass (2026-09-27): reliability, behaviour and polish across the core, brain, firmware, face, Mac app and tools | Done. The final firmware `cf6d8ae` matches the simulator on the board in all 10 scenarios, `perf --motion` passes and `make -C internal e2e` passes; the new looks still need watching in motion (check 1) | [evidence](evidence/2026-09-27-overnight/) |
| A10 | Jev-only harness: typed events and transcript, a plain-text state, mood and personalities ([harness/](harness/HARNESS.md)) | Done; the evals pass against Jev; checks 12–16 are the owner's | [evidence](evidence/2026-09-27-jev-harness/README.md) |
| | Production and internal code split: what doesn't ship moves to `internal/`, `Package.swift` to the root ([internal/README.md](../internal/README.md)) | Done; the evals pass against Jev, 7/7 in all 3 runs | [evidence](evidence/2026-09-27-internal-split/README.md) |
| A11 | Seven moods, drawn from the mood SVGs: Jev picks the mood, and the device shows each state and reaction in it | In progress. Jev chooses among the seven moods with no minimum time between changes (evals 10/10 in all 3 runs); every `state` carries the mood; the device draws each look and the cheer as the mood's design, exactly as Chrome draws the SVGs. The popover's tile shows the same faces. Still to do: watching it on the board | [moods](evidence/2026-09-27-seven-moods/README.md), [faces](evidence/2026-09-27-mood-faces/README.md) |
| A12 | Live dashboard: `internal/tools/boopctl dash` shows the state and face, the harness's passes and a timeline, and forces a mood, a reaction or an animation ([DASHBOARD.md](DASHBOARD.md)) | Done, headless; check 20 is the owner's | [evidence](evidence/2026-09-27-dashboard/README.md) |
| A13 | Reaction faces: `react` picks one of the seven moods' faces, and the device draws the look in it while the mumble plays ([harness/DECISIONS.md](harness/DECISIONS.md) §3, [PROTOCOL.md](PROTOCOL.md) §3) | Done in code and the simulator; `make eval` passed 10/10 in all 3 runs; watching it on the board (check 1) is the owner's | [evidence](evidence/2026-09-27-reaction-faces/README.md) |
| A14 | Loops and pending: every animation can loop and whoever plays one says how many times; HISTORY shows what Boop started as in progress until it really ended, and the device says when a moment ended ([harness/HARNESS.md](harness/HARNESS.md) §4–5) | In progress. Done: the harness's started actions (`.started` with a `Pending`, `settle` entries, a ceiling on waiting, and HISTORY's `(in progress)` and `(didn't happen: …)`); `react` is started, and ends when the device says how its moment ended (`ended`: done, cut short and by what, or skipped, [PROTOCOL.md](PROTOCOL.md) §4), or `failed` when dropped, with no device, on a disconnect or when no `ended` comes in time ([harness/DECISIONS.md](harness/DECISIONS.md) §5); checked on the board over USB. Still to do: loops. "Done, not reviewed" sessions are out of scope | [ended](evidence/2026-09-28-tonight/loops-pending/README.md) |
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
   sway and heart. Then a reaction (A13): the dashboard's `r` (check 20)
   switches the look to that mood's face while the mumble plays, and
   back. Say what you'd change.
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
   only after 50 ms without contact. With Jev's key, the fourth quick tap
   may also get a grumpy face and mumble, and more tapping gets no second grumble
   within a minute ([BEHAVIORS.md](BEHAVIORS.md) §3.3).

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
   keyboard, in Boop's mood), then a cheer that switches to proud's cheer
   while a proud mumble plays, nearly always with a word.
10. **Ask Claude to run a failing test, then stop.** No cheer: Boop goes
    idle, then a grumpy face and mumble ("tests" or "ugh"), and back to
    its mood's face.
11. **Esc while Claude is between tool calls.** Within about a minute Boop
    goes idle, with no cheer; at once if a tool was running.

**Personalities and the brain**

12. **Paste Jev's key in Settings, then work normally for a while.** The
    Personality card loses its "Without a Jev API key, … only cheers,
    wiggles and chatters by rule" line. Routine
    turns go by quietly; a very long finish gets a proud face and mumble
    on top of the cheer ([harness/DECISIONS.md](harness/DECISIONS.md)).
13. **Let tests fail three times in a row, then pass.** On the third
    failure a grumpy face and mumble ("…again!" or "…tests!") and Boop
    turns grumpy (the `mood` file in `~/Library/Application Support/Boop/`);
    when they pass, a proud "…finally!" and Boop turns proud
    ([harness/EXAMPLE.md](harness/EXAMPLE.md)).
14. **`Boop --debug` (`make debug`) through a turn.** The terminal shows
    each event, the pass with Jev's whole state the first time and its
    answers, and what the actions did; `boop.log` has one `brain …` line
    per pass and none of the state ([harness/HARNESS.md](harness/HARNESS.md)
    §9).
15. **Settings → Personality: Chatter for a while, then Boop.** Chatter
    shows a "Chatter" chip, mumbles at nearly everything, including
    routine tool use, and chatters every 30–60 s while agents work. Boop
    is back to speaking up only when something stands out
    ([BEHAVIORS.md](BEHAVIORS.md) §6).
16. **`BOOP_JEV_KEY=… make eval`.** Every scenario passes in all three
    runs ([EVALS.md](EVALS.md)).

**The Mac app and the link**

17. **The popover and the menu-bar icon in light and dark, with an
    approval waiting.** The Warm Terminal look ([UX.md](UX.md) §6), with
    the needs-you icon's deeper amber clear on a light menu bar. In the
    active popover, setup's switches are sage when on and the volume
    slider fills in ink, which `Boop --snapshots` can't show.
18. **Over Bluetooth, an approval arriving as a turn finishes (two
    sessions); separately, BOOT pressed again within a second of letting
    go.** The screen always matches the popover, and the second press is
    heard ([evidence](evidence/2026-09-26-e2e-hardening/README.md)).
19. **Settings → Device → Reconnect; then `kill -9` the app and `make run`
    again; then quit it and wait 30 s.** Both reconnects find the board
    within a couple of seconds, the second by taking over the link macOS
    kept ([PROTOCOL.md](PROTOCOL.md) §2). After quitting, the board shows
    the no-app design with only the unplugged icon.
20. **`make debug`, then `internal/tools/boopctl dash` in another terminal.** The
    dashboard's face shows what the board shows, though not frame for
    frame. `m` grumpy, `r` grumpy with "again", and `a` cheer each land
    (no warning after 2 s), and the board plays the reaction (the look in
    grumpy's design while the mumble plays) and the cheer.
    Then quit and `make run`: the same keys warn that nothing landed
    ([DASHBOARD.md](DASHBOARD.md) §4).

## 3. Open items

Known work that isn't a milestone yet, including drift found and not
fixed. Pick one up by writing it into its spec first.

- **Release.** There's no signing, notarisation, app icon or release
  pipeline yet.
- **The landing page is out of date.** [Its copy](../landing/src/lib/copy.ts)
  describes an older Boop that approved and denied from the device, which
  [VISION.md](VISION.md)'s promises now rule out, and agents v1 doesn't
  watch (Cursor, VS Code). It needs rewriting to match v1.
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
- **The reaction faces haven't met Jev.** The eval scenarios expect the
  new `react` options (`grumpy` for `annoyed`, and `sad` or `determined`
  where they fit), but `make eval` needs the owner's key. The Jev lines in
  [harness/EXAMPLE.md](harness/EXAMPLE.md) and
  [harness/HARNESS.md](harness/HARNESS.md) §9 predate the change and say
  `annoyed`; the next `make eval` should record them again.
- **The dashboard's recorded run predates started actions.**
  `internal/tools/boopctl_lib/tests/fixtures/headless-debug.jsonl` has
  `react` lines with no `"pending":true` and no `settle` lines;
  `test_dash.py` checks those with lines of its own. The next recording
  of the fixture ([DASHBOARD.md](DASHBOARD.md) §7) brings them in.
- **A settle recorded while Jev answers spoils an exact rebuild** of
  that pass's state from `debug.jsonl`
  ([harness/HARNESS.md](harness/HARNESS.md) §5.3). Since `react` waits
  on its moment, one the device says ended during a pass does it. Logging
  on the pass the last `seq` its state saw, or holding settles while a
  pass runs, would make it exact again.
- **`make -C internal e2e` fails one expectation it can't meet.**
  `internal/app/Tests/Fixtures/hooks/e2e/expect.json` wants an event
  with "claude's deploy failed on", but the Claude fixture's deploy is a
  `PreToolUse` followed by `StopFailure`, with no failed tool result, so
  the core records "failed (rate limit)" instead. Every checkpoint
  passes. Drop the expectation, or give the fixture a failed deploy
  result ([evidence](evidence/2026-09-28-tonight/loops-pending/README.md)).
- **Determined has no voice.** Its reactions mumble in the temporary
  default, happy's, while the audio is tuned ([VOICE.md](VOICE.md) §4).
- **Most of Voice's words can't be picked.** The `react` action offers
  11 of the 40 real words (7 exclamations and 4 topics,
  [harness/DECISIONS.md](harness/DECISIONS.md) §3); the rest are recorded
  on the device for nothing until the lists grow.
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
- **About 14 KB of heap headroom.** The minimum free heap, 74 KB, is
  only just over the 60 KB target ([DEVICE.md](DEVICE.md) §6), so
  anything that adds RAM needs measuring.
- **A freshly built `boop-hook` is slow once:** about 250 ms on its first
  launch while macOS checks it, then a few milliseconds.
- **`swift build` rebuilds for no reason.** It alternates between a
  no-op (0.4 s) and a 6–9 s rebuild with nothing changed, so build
  timings are noisy until the cause is found.
- **`state`'s `idle` and `wait` are only the dashboard's.** The device
  keys "needs you" on `attn` and reads neither
  ([PROTOCOL.md](PROTOCOL.md) §3); the dashboard's feed prints both.
  `wait` is always 1 + `attn.more` (0 without `attn`), so it can go once
  the dashboard counts it from `attn`.

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
