# Mood spectrum V4: integration plan

Updated 2026-09-29. How the design package on `codex/boop-mood-spectrum-v4`
(`72ca30df`, `internal/boop-design/`) becomes the shipped Boop: 13 moods on
Jev's mood graph, 22 activity states, 770 performances and their sounds,
on the Mac and the board. It's a work plan, not a spec. Each phase updates
the specs it touches, as CLAUDE.md's table says.

## 0. What the package is, measured

| Fact | Measured how |
| --- | --- |
| 13 moods, 98 one-way edges (ordinary and dramatic), hold always allowed | `validate.mjs` |
| 22 states × 13 moods = 770 performances; the 7 older moods have 44 each (V3), the 6 new ones 77 (V4) | `build.mjs` coverage |
| Our 161 shipped SVGs are **byte-identical** to the older-mood part of the bank | `cmp` of every file |
| Three SVG dialects: V2 (`boop-motion`, what facegen reads), V3 states (`state-motion`), V4 moods (`motion`, a flipbook of whole-face frames) | tag census |
| V3 and V4 art repeats the face in each frame, so facegen's "one face, a mouth" check fails; the generator already tags `face`/`mouth`/`eyes` (`visual/base.mjs:177,185`) | facegen run |
| With those checks relaxed, facegen reads all 770 into 704 distinct scenes, **about 1,450 KB** of faces (today 286 KB); the largest scene fits `kMaxGroups` 270; the most variations in one state is 9 | facegen probe in a scratch worktree |
| Faces by part: 13 moods × today's 7 states 587 KB; 7 older moods × 22 states 708 KB | the same probe on subsets |
| Sound effects: one clip per effect, so 13 moods add only 2 new clips (`failedAttempt`, `brake`); scores are small tables | `sfx.h` layout |
| The bank reworks the older moods' sounds (a quieter, voice-first mix): 98 of our 140 shipped scores differ | score diff |

**Flash.** `min_spiffs.csv` gives app0 1.875 MB, and the firmware is 1.52 MB
with 286 KB of faces. Everything means about 2.7 MB. Nothing uses the second
app slot (no over-the-air update exists), so the plan switches to the
standard `huge_app.csv`: one 3 MB app slot, the same NVS offset (touch
calibration survives), coredump kept. That leaves about 14% free.

## 1. Concepts, old to new

| Concept | Today | After |
| --- | --- | --- |
| Mood | 6 for Jev, 7 in art (curious) | 13, on the graph; Jev picks hold or a neighbour |
| Visual (state) | 7: idle, working, needs_you, task_complete (brain's cheer only), asleep, no_app, listening | 22; the core picks it from hook evidence, with priorities (§4) |
| Reaction | `react.mood` of 6, `react.animation` none or cheer | `react.mood` of 13; cheer plays task_complete in the mood picked (see decision D2) |
| Poke | device wiggle, 0.7 s | `poked` design; 3+ taps within 3 s play `tap_spam` (device-side count, the Mac's constants) |
| Sound | 140 scores, V2 mix | 770 scores, V4 mix, per-loop choice of which routine contacts sound |
| Voice feeling | 6 moods map to 8 feelings | 13 map; new moods borrow existing feelings until the recorded voice arrives |

## 2. Phases

Each phase ends green (build, Swift tests, firmware tests, goldens it
touches) and commits separately, with its spec updates.

**P0. Base.** Fast-forward to `72ca30df` (the package), start `caffeinate`,
record baselines: firmware size, free heap from the simulator, test counts.

**P1. One source for the art.** The bank's generator becomes the source of
`facegen/design/`: a small export script writes the SVGs and a trimmed
manifest (mood, state, variation, name, seconds, `outcome`,
`startContext`). Generator changes so each design has exactly one tagged
face and mouth (a flipbook frame's face becomes one face group with a
move track, or facegen learns "the visible frame's face"; pick whichever
keeps Chrome parity). V2 designs must come out byte-identical.

**P2. facegen and the renderer.** facegen reads the three dialects, allows
a different variation count per mood × state (the older moods have 1 where
new ones have 3), and writes per-variation metadata (outcome, start
context). Firmware: `Mood` 13, `SceneState` 22, the scene table indexed
by mood × state with its own counts, variation filters by outcome and
context. Partition switch. `facegen --check` against Chrome for all 704
scenes; `test_face`, `test_scene` frames, simulator goldens re-accepted
after looking.

**P3. Sounds.** No recipe changed; the bank only adds `brake` (stopped),
`failedAttempt` (task failure, error) and uses the existing `knock` (new
moods' needs-you taps): 3 clips, about 10.6 KB, so sfx.h goes to about
160 KB of its 180 KB cap. sfxgen imports the bank's `makeScene` rather
than reading its ignored manifest, and bakes the V4 mix: for each
routine score, the event lists `routineEvents` gives for loops 0..7
(seed 53), and EffectTrack plays loop `n % 8`'s list. Sparse counts
loops, as the bank does, not wall time. Ducking moves from "clips named
alert" to "scores of needs_you, task_complete and error aren't ducked";
everything else ducks to 0.25 under a mumble, the bank's level. A
mumble starts at the design's voice window (after the attention cue),
and a line that doesn't fit extends the hold rather than being sped up.
`test_effects`: clip count, budget, idle now silent, working now
thinned, the duck rule.

**P4. The 22 states on the Mac (core rules).** Evidence per state is in §4.
The core keeps each session's current tool (id, category, topic) and
turns it into a sustained activity; one-shots go out as moments. The
`state` line gains `act` (sustained activity) and moments gain
`anim` values for the one-shots, with `outcome` and `ctx`; old firmware
ignores both. The finish (D2): a question, `finish.outcome`, asked on
passes where a turn ended, decides task_complete (success or failure) or
reply_ready; the react action carries it out. New hooks: `SessionStart`'s `source`, Claude's
`SubagentStart`. A short minimum show time stops fast tools flickering.
The variant picker and `FaceLoops` key on the visual. Headless e2e and
`workday` exercise every state.

**P5. The states on the device.** Behaviour takes `act` and the new
moment anims, keeps the priority order (§4), plays `poked` and counts
`tap_spam` itself, filters task_complete by outcome and starting by
context. no_app and asleep stay shared across moods.

**P6. Moods and the graph.** `MoodGraph` (the JSON, bundled, checked
against the package copy). Mood selection is dynamic: `MoodAction.questions()`
builds the options on every pass from the saved mood, hold plus that
mood's graph neighbours (ordinary and dramatic, D3) and nothing else,
each with its mood's one-line meaning; dramatic ones carry a `notFor`
("only after a fresh, big event"). `run()` accepts only hold or an edge
from the current mood. The generic harness needs no change: it asks
`questions()` when it prepares a pass, and a mood changed mid-pass by the
dashboard already makes `mood` sit the pass out. The debug log records
each pass's options, so the dashboard shows the current neighbours; its
own "set mood" stays unrestricted.

`ReactAction`: `react.mood` offers none plus 13 faces (a moment's face,
never the lasting mood). `react.animation` becomes `none | success |
failure | reply` (D2): success when the turn-end text says the work is
done and working, failure when it says the agent couldn't or something
is broken, reply for an answer or question back that isn't a finished
task; the device plays task_complete with that outcome, or reply_ready.
It's asked on every pass (actions never read facts), `none` when NOW
isn't a turn ending. No code override for failed turns: HISTORY already
says "failed", and an always-eval pins that Jev picks failure then.

`Voice.feeling(forMood:)` for 13. Seven new steering files (and their
bundled copies) within the 175-token budget; the "leaves for" lines name
graph neighbours only. Resting mood (D4); the hourly fade walks the graph
one step toward it. Tests: each mood's options equal its graph row plus
hold; grumpy is never offered happy or excited; a non-neighbour answer
changes nothing; the graph is strongly connected on ordinary edges;
react.animation's four options map to the right device anim and outcome.

**P7. Evals.** The runner learns the new fields: `animation` values
`success|failure|reply`, and an `offered` check (the mood question's
options on that step equal the graph row), so a scenario can pin the
graph. Existing scenarios: the 27 that expect a mood and every one that
expects `cheer` are rewritten for the new names (happy as the resting
mood becomes calm where that's what's meant; cheer becomes success or
reply), each keeping its plain-English `case`.

New scenarios, `always` where they guard character or safety:

| # | Scenario | Checks |
| --- | --- | --- |
| 41 | A turn ends "all tests pass, pushed" | animation success (always) |
| 42 | A turn ends "I couldn't get the build to work" | animation failure, never success (always) |
| 43 | A turn fails (StopFailure / failed last check) but its message sounds upbeat | failure, never success (always) |
| 44 | A turn ends with a question back to the person | reply, not success |
| 45 | A turn ends with an answer to a question, no work | reply |
| 46 | A finish in a sad or grumpy mood | the outcome still follows the text (success stays success in a sad face) |
| 47 | Recovery walk: grumpy, then quiet good work for a while | moves only along edges (grumpy → irritated or annoyed → engaged → calm), never grumpy → happy (always) |
| 48 | One big failure from calm | a dramatic move is allowed (wounded or sad); a small failure from calm stays ordinary (annoyed) |
| 49 | Pokes from calm: one, two, three in a row | calm → curious or happy, then annoyed, then irritated/grumpy, only along edges (always) |
| 50 | Thanks while whiny or wounded | back toward calm or happy along an edge, a dramatic happy allowed |
| 51 | A long grind of passing work | engaged or determined, not excited until it ends |
| 52 | Routine work in a calm mood | hold: no mood change for ordinary tool calls (no bouncing) |
| 53 | Every step of a busy day | the answer is always among the offered options (always, whole run) |
| 54 | Talk while irritated | the face and word fit irritated, not grumpy |
| 55 | Heartbeat with nothing happening, from excited | fades one edge at a time toward calm |

States that are pure rules (terminal, testing, error, stopped, starting,
helper_return…) are checked by Swift tests and `workday`, not evals: the
brain doesn't pick them. Jev runs need the owner's `BOOP_JEV_KEY`; without
it the scenarios are written, pass their format check, and are run
against the scripted brain only, and the evidence says they're unrun
against Jev.

**P8. Mac UI and tools.** Popover tiles and `--snapshots` for 13 moods;
`boopctl` mood and state lists, the dashboard (it reads the question
list already), soak's random moods.

**P9. Board (owner: yes).** Over USB only (`boopctl bridge` + `Boop --headless --link
usb:…`), never Bluetooth: flash, then walk every state in a few moods,
`perf --motion` for free heap, a soak. Webcam only if the owner asks.

**P10. Specs, review, evidence.** VISION scope, ARCHITECTURE (decision log:
partition, 22 states, graph), BEHAVIORS, DEVICE §5–6, PROTOCOL, ADAPTERS,
EVENTS, HARNESS, DECISIONS, VOICE, VERIFICATION, EVALS, CLAUDE.md/AGENTS.md
table, `internal/boop-design/README.md` (no longer "not integrated"). A
code review pass. The branch is left for the owner; nothing merges to main
without a go.

## 3. Decisions

Defaults the night runs with unless the owner says otherwise.

| # | Decision | Default |
| --- | --- | --- |
| D1 | Partition | **Owner: yes.** `huge_app.csv`: one 3 MB app slot, no second slot |
| D2 | Task complete | **Owner: the brain decides.** When a turn ends, Jev judges the outcome from the turn-end text (the agent's last message): a new multiple-choice question, success, failure, or not a finished task (reply_ready). A host fact wins over the brain: `StopFailure` or a failed last check is always failure. The finish plays as the brain's reaction (the brain stays off the screen's path), in the mood it picks |
| D3 | Dramatic moves | **Owner: edges only.** Code offers hold plus every neighbour, ordinary and dramatic, and rejects anything else; each dramatic option carries a "not for" saying it needs a fresh, big event |
| D4 | Resting mood | calm (the handover's suggestion); the hour-long fade goes to calm |
| D5 | Mood pacing | **Owner: steering only.** No dwell or reversal timer in code |
| D6 | Older moods' sounds | Take the V4 mix |
| D7 | error state | Only exit-code and timeout failures, at most once per 30 s; a denied request never shows as error |
| D8 | planning | Claude's plan mode, `TodoWrite`/`ExitPlanMode`, Codex `update_plan` if its hooks report it; otherwise the state doesn't show |
| D9 | New art approval | Integrated as-is; the owner's visual and listening approval comes before any merge to main |
| D10 | Speech bubble | Today it sits over y 144–204 and hides props; the new art keeps y 192–240 free for text and its props are the action. The bubble moves into that bottom lane for every design, wrapping or paginating, and prop-hiding goes |
| D11 | Unknown saved mood | Logged, read as the resting mood (D4) |

## 4. The 22 states: evidence and rules

Priority, highest first: no_app, listening, needs_you, device one-shots
(poked, tap_spam), Mac one-shots (task_complete, reply_ready, stopped,
error, helper_return, starting), sustained tool states (testing >
delegating > terminal > searching > analyzing > tool_use), waiting,
planning, working, idle, asleep. With several sessions, the most recent
event among working sessions picks the activity; one-shots from any
session play, but not while needs you shows.

| State | Evidence (Claude Code / Codex) | Kind |
| --- | --- | --- |
| no_app | device: 30 s without a `state` | sustained, device |
| asleep, idle, working, needs_you, listening | as today | as today |
| starting | `SessionStart` source startup/clear → session; resume/compact → continuation; `UserPromptSubmit` → new_task | one-shot |
| planning | D8 | sustained |
| terminal | Bash / shell, exec_command, local_shell | sustained |
| tool_use | any other tool (edit, MCP…) | sustained, fallback |
| searching | WebSearch, WebFetch / none seen from Codex | sustained |
| analyzing | Read, Grep, Glob, LS / shell `rg`, `grep`, `cat`, `sed -n`, `find`, `ls` (a new topic tag) | sustained |
| testing | `topic == tests` on the tool | sustained |
| delegating | Task/Agent tool start, until its end or every helper's `SubagentStop` / none | sustained |
| helper_return | `SubagentStop` for a helper Boop saw start | one-shot |
| waiting | a tool running with nothing heard for 20 s, or Codex's request grace | sustained |
| reply_ready | turn done, outcome unknown (all Codex turns; Claude turns with no tool calls) | one-shot |
| task_complete | turn done with a known outcome: success, or failure (StopFailure, last check failed) | one-shot, outcome |
| error | a failed tool call, D7 | one-shot |
| stopped | interrupt, Esc, Codex Interrupt | one-shot |
| poked, tap_spam | device taps | one-shot, device |

Codex gaps: no searching, delegating, helper_return or error, and every
finish is reply_ready.

## 5. Risks

- facegen parity with Chrome on the new dialects (flipbooks, clip at
  y=192) may need renderer work; `--check` is the gate.
- The speech bubble starts at y=144 and hides props below it; the new art
  keeps y=192–240 free. The bubble may need to sit lower for new designs.
- Blink: flipbook art bakes its own blink, so the device's blink clock
  doesn't apply to it.
- A 2.7 MB image flashes in about twice the time.
- Jev evals can't run without the owner's key.

## 6. Contracts the lanes share

Fixed before the lanes start, so they can work in parallel.

**Mood order** (firmware `render::Mood`, facegen, sfxgen, boopctl, `FaceLoops`):
happy, excited, proud, curious, determined, grumpy, sad, calm, engaged,
annoyed, irritated, whiny, wounded. The first seven keep their numbers.

**State order** (`render::SceneState`, facegen `STATES`, `FaceLoops.states`):
idle, working, needs_you, task_complete, asleep, no_app, listening, then
starting, planning, terminal, tool_use, searching, analyzing, testing,
delegating, helper_return, waiting, reply_ready, error, stopped, poked,
tap_spam. The first seven keep their numbers.

**Variations.** A mood × state has its own count (1–9). Each variation
may carry `outcome` (`success`/`failure`, task_complete only) and `ctx`
(`new_task`/`session`/`continuation`, starting only). facegen writes both
into faces.h and `FaceLoops.swift`, with
`FaceLoops.count(mood:state:outcome:ctx:)` and `ms(mood:state:variant:)`.
A variant number is 1-based within its mood × state, over all its
variations; filters pick among those that match.

**`state` line** gains `act`, optional: one of planning, terminal,
tool_use, searching, analyzing, testing, delegating, waiting. The visual
is needs_you with `attn`, else `act` while `base` is `working`, else
`base`. `variant` is that visual's. Old firmware ignores `act`.

**`moment.anim`** gains: `starting` (with `ctx`), `helper_return`,
`error`, `stopped` (rule moments from the core, no `id`, no brain), and
`task_complete` (with `outcome`) and `reply_ready` (the brain's, from
`react.animation` success/failure/reply, with `id`, `loops`, `mood`,
`who`). `cheer` stays readable as task_complete success, and the Mac
stops sending it. `wiggle` stays for the dashboard; a tap plays `poked`.
One-shots play once (or `loops` times) and hand back to the look;
none plays while `attn` or listening holds the screen.

**Taps.** The device counts taps itself: a tap within 3 s of the last
extends the run; the 3rd and later play `tap_spam`, the others `poked`
(the Mac's `inARowMs` 3000 and `answersRunFrom` 3).

**Ownership.** Lane art (`ms/art`): `internal/boop-design/`,
`internal/tools/facegen/`, `internal/tools/sfxgen/`, `firmware/` (render,
voice, effect track, assets, partition, then behaviour for the states),
`internal/firmware/`, generated `FaceLoops.swift` and `FaceDesigns.swift`,
`boopctl`. Lane states (`ms/states`): `app/HookWire/`, `app/BoopHook/`,
`app/BoopKit/Adapters/`, `app/BoopKit/Install/`, `app/BoopKit/Core/`
(but not the generated files), `StateSnapshot`, `DeviceMoment`, rule
moments, `Runtime` wiring. Lane moods (`ms/moods`): `app/BoopKit/Actions/`
(Mood, React), `MoodGraph`, `app/BoopKit/Voice/`, `plan/steering/` and
its bundled copy, `internal/app/Evals/`, `internal/app/BoopDevKit/Eval/`.
Each lane updates the specs for its files. Shared hotspots
(`Runtime.swift`, `DeviceMoment.swift`, the ARCHITECTURE decision log)
are merged by the orchestrator.

## 7. Status, 2026-09-29

Done: P0–P10 on this branch (the lanes merged, the board checked over
USB, the specs swept and the decision log written); what ran is in the
[integration's README](README.md). Left: the Jev evals of the final
steering with the states merged (the key ran out of credit), the owner's
look and listen (D9), and anything over Bluetooth. `/simplify` and the
webcam pass come after this.
