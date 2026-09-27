# Overnight pass (2026-09-27)

What changed overnight, what was checked, and what's left for you. Everything
is on branch `claude/buddy-reliability-polish-2588ff`; `main` is untouched.

## The short version

- **The hero moments hold up.** Two audits traced every hero use-case end to
  end and found real bugs in "needs you" and in how turns end. They're fixed
  and pinned in tests. The worst ones: parallel subagents erased a pending
  approval, Esc between tools (or on a permission prompt) left Boop amber
  or "working" for up to an hour, and a failing `grep "make test"` could turn
  a finished turn into a failed one.
- **Every mode is now deterministic and checked.** Normal had no rules of its
  own and behaved like chatty without Jev's key. It now has its own table,
  which also takes over whenever Jev fails. `make eval` checks all three
  modes: 15 scenarios, 45 passes out of 45. With Apple's model writing the
  words it passes 3 runs out of 3.
- **Two commands for debugging.** `make debug` prints everything live in one
  terminal: hooks, decisions, device lines, and every brain pass with what
  the brain read and wrote. `make eval` / `make eval REAL=1` runs the evals.
  The README is one page.
- **A design pass on both screens.** The device face now moves as one
  pixel sprite, breathes with a one-block bob, keeps its sprites on the 3 px
  grid and never lets them collide. The Mac app uses the device's Warm
  Terminal look (black glass, one amber accent), with a pixel-crisp face
  and menu-bar icon.
- **The specs are current and shorter.** PLAN.md went from 838 lines to about
  230, and each fact lives in one place. The finished v1 build plan and the
  full decision log moved to `archived/plan-v1-build/`.

## Trying it

```sh
git -C ~/src/buddygotchi merge --ff-only claude/buddy-reliability-polish-2588ff   # main hasn't moved
make flash        # the board already runs the final build (cf6d8ae); only needed after later changes
make debug        # or make run
```

On first launch Boop repairs your Claude hooks (they gain `idle_prompt`), so
restart open agent sessions once. To run the evals with Jev deciding normal,
from your own terminal:

```sh
BOOP_JEV_KEY=$(security find-generic-password -s com.boopcomputer.boop -a jev -w) make eval REAL=1
```

What to look at first is [PLAN.md](../../PLAN.md) §2 (owner checks).
Check 1 is watching the new face move; nobody has seen it in motion yet.

## What was checked

| Check | Result |
| --- | --- |
| Swift unit tests (`make test`) | 255 pass (210 at the start) |
| Evals, deterministic (`make eval`) | 45/45: 15 scenarios × chatty, normal, calm (24 at the start, chatty and calm only) |
| Evals with Apple's model (`make eval REAL=1`, no Jev key) | 45/45 in each of 3 runs, 0 refusals, writer p50 about 1.5 s |
| Firmware tests (`make fw-test`) | 118 pass |
| Simulator vs goldens (`tools/boopctl sim`) | 10 scenarios, every changed golden looked at before accepting |
| Board vs simulator (`tools/boopctl run`) | 10 scenarios, pixel-identical, final firmware `cf6d8ae` (flashed) |
| Board in motion (`tools/boopctl perf --motion`) | ok; 23 frames drawn a second on average, 73.8 KB heap free |
| Hook → app → board (`make e2e`) | pass, p50 37 ms from hook launch to the device |
| Tools' own tests (`make tools-test`) | pass |

Not checked: Jev live (agent shells have no key); anything over Bluetooth
(agents can't use it); the webcam (a framing clip only, then you asked me not
to); the new looks in motion by eye. The machine slept from about 03:30 to
09:20, so the work ran in two stretches.

## What changed

Every behaviour change is its own commit, so you can revert any one. The face
commits and the Mac palette commits stack (later ones edit the same lines),
so reverting an early one means reverting the later ones in its group too.
Lane-by-lane detail and pictures are in the subfolders here.

### Needs you and turns ([core](core/README.md), second pass in `core2`)

| Commit | Change |
| --- | --- |
| `db18ef0` | A sibling subagent's tool events no longer clear "needs you" |
| `7a8e728` | Hooks subscribe to Claude's idle notice, so an Esc between tools ends the turn |
| `19eec5f` | That idle notice also clears the main agent's request (Esc on a permission prompt sends nothing else) |
| `baa07f9`, `ec2cf50` | A command's topic comes from what it runs, not a word anywhere in it |
| `4d54b7b`, `6622726` | The 10-minute safety net leaves a session idle, including a Codex request still in its grace |
| `76ea654` | Claude's real API error values map to the right classes |
| `9f6fa20` | Documented (no change): an approved long command keeps amber until it finishes; Claude has no approval hook |

### Talking to Boop and quiet

| Commit | Change |
| --- | --- |
| `b95c50e` | No working chatter or agent mumble while you talk; chatter never cuts a reply |
| `6add652`, `06a2e48` | When Boop decides not to reply, or the mic fails, listening ends right away instead of after 8 s |
| `e266e1e`, `e7869f6` | A turn finishing while you talk doesn't replace the listening face with a cheer |
| `c86fe79` | "You can talk again" ends quiet (before, it started another 30 minutes) |
| `d062eba` | Quiet lasts about as long as you asked: 10 minutes is 15, three hours is 120 |
| `0a04948` | A yell decides a sad reply only when the words say nothing else ("GOOD JOB!" is still praise) |
| `46d9ada` | A greeting counts only at the start of what you said |
| `a6f4f64` | Talking first thing in the morning starts the day (the note used to land in yesterday's file) |

### Memory, modes and the brain ([brain](brain/README.md))

| Commit | Change |
| --- | --- |
| `8b69fe5` | Normal gets its own if-else table |
| `8644dbf`, `4a191c8` | When Jev fails or is late, normal's table decides, with time left to write |
| `131c80b` | `react` loses its `silent` voice: a react is a mumble, and asked for quiet Boop is just quiet |
| `15a3a91`, `6103e45`, `fc8733a`, `d8639f0` | Remember routing: a name goes to today (Boop's own name doesn't count), "remember" wins over "quiet" everywhere, curly apostrophes work |
| `38b3ddd`, `b983852`, `43c2b51` | The writer samples greedily, reads only the latest five Happened lines (faster), and won't pass off an old memory line as the new one |
| `250ec50`, `e1ea494` | Steering: "okay" for a request, and lines that couldn't apply are gone |

### The device ([fw](fw/README.md), [face](face/README.md))

| Commit | Change |
| --- | --- |
| `ebdaf7a` | The working face actually animates on the board (it only redrew during blinks) |
| `808e87f`, `c232cd8` | The board draws a frame only when the picture changes, at most every 16 ms |
| `2928ecc`, `1aad5be` | Timers survive the millis() wrap (the asleep face froze after 25 days); a frozen debug clock thaws |
| `a59609c`, `8722e5f`, `4f29089`, `27e4883` | Taps reach every live Mac link (a tool's injected ones only USB); one light press is one tap |
| `3486378`, `c4d7868`, `4e75d2a`, `78fcd1e` | No-app strip shows only the plug; no invisible reconnect blink; no debug label; no click when a line is cut |
| `294ca4b` … `04497af` | The face as one sprite, equal working eyes, a one-block bob, sprites on the grid, no heart/drop overlap, needs-you face at 85%, a cheer that squashes on landing with a beating heart, the word never loses room to squiggles, plain letters for accents, a coral heart, heavier shut eyes |

### The Mac app ([mac](mac/README.md))

`e549712` Warm Terminal palette (this reverses your 2026-09-26 preference for
gen-2's Boop Cream, so look at it first), `cd2e30c` a pixel popover face,
`795bc73` a crisp menu-bar icon that shows needs-you on a light bar, and
edge states: stable session order, a human "couldn't start", settings with
the Jev key only in Normal, hook errors on the agent row, and the full
project name on the needs-you card.

### Commands and tools ([tools](tools/README.md), second pass in `shell2`)

| Before | After |
| --- | --- |
| `make run DEBUG_LOG=…`, `--trace`, `--debug-log`, and `boopdev watch` in a second terminal | `make debug` / `Boop --debug`; `boopdev watch` reads a saved `debug.jsonl` |
| `make eval` (chatty and calm), `boopdev brain` for the real models | `make eval` (every mode), `make eval REAL=1` |
| 26 `boopctl` commands | 14 (`play` and `send` absorb the hear-it and inject commands) |
| `boopdev` with 8 commands | 6 (`brain` folded into `eval --real`, `memory` gone) |
| `tools/build-loop.sh`, `plan/LOOP.md`, 16 MB of gen-2 evidence, a CI file that couldn't build | gone (tags keep them) |

Safety fixes: a mistyped `Boop` flag stops with its usage instead of starting
the Bluetooth app and repairing your hooks; `--headless` never reads your
Keychain; a Boop on another `--state-dir` leaves your real hooks alone;
push-to-talk no longer crashes a Mac with no microphone; enabling Codex hooks
can't write `[features]` twice.

### Cleanup (`/simplify`)

Four reviewers (reuse, simplification, efficiency, altitude) read the whole
overnight diff, and 33 behaviour-preserving cleanup commits went in on three
branches (`ovn/s1`, `s2`, `s3`, merged): the runtime builds its brains in
one place, the core's calendar goes through one wall-clock helper, the
writer reads memory through the store's own parser, events and effects
describe themselves, `Boop` and `boopdev` share one argument parser,
`boopdev eval` picks brains the way the app does, Settings stops asking
Apple's model on every redraw, and the firmware lays the face out once per
frame with one block-rectangle and one clamp helper. Snapshots, goldens
and a 60,000-tick firmware hash stayed identical; only a few CLI error
messages read differently (`--mode is chatty, normal, calm`). Skipped, because each
would change behaviour or reach well past the diff: merging the core's
three push-to-talk variables into one state (it drops an empty moment the
device ignores), moving the writer's copy check into the memory store,
handing each action the pass's input instead of the core's quiet flag, and
making the installer refuse writes for another state directory itself.

### Speed

boop-hook takes half as long per hook (p50 7.6 → 3.8 ms, debug build); the
writer's median dropped to about 1.5 s by reading less memory; the word list
and Voice's syllable pools load once; project names are cached per folder
instead of reading `.git` on every hook; the firmware stops redrawing
identical frames.

## Left for you

- **Decisions I didn't make** (all small; each would be one commit):
  treating "hush", "stop talking" and "keep it down" as asking for quiet (they
  count as telling Boop off today); letting calm reply when told off; one
  working pace instead of a faster one at 3+ busy sessions; dropping chatty's
  second try for a missing word; sending "agent started" to the brain only in
  chatty.
- **Jev live.** Run the command above; normal's expectations are what Jev
  should do.
- **Open items** are in [PLAN.md](../../PLAN.md) §3, including a denied
  subagent's request staying amber until the turn ends (needs a SubagentStop
  hook) and Temperament/Moments no longer growing.
