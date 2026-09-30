# Here and away

2026-09-29. The owner's brief: Boop should know when you step away from
the Mac and come back, with the deciding kept in the trigger, out of the
harness, the view and the core. Only coming back does anything; a wrong
away (a long video) must never make Boop go quiet.

## What changed

- **The detector** (`app/BoopKit/Presence/PresenceDetector.swift`) is the
  only code that decides. Away after a 30 s lock or sleep, or 30 minutes
  of idle; back on a touch within 5 s once unlocked and awake.
  [harness/EVENTS.md](../../harness/EVENTS.md) §2.1.
- **The signals** (`app/Boop/PresenceSignals.swift`): lock, unlock,
  user switching, sleep and wake notifications, and the idle time. None
  asks for a permission.
- **The event**: `presence`, source `mac`, a start for away and an end
  for back, recorded in the transcript through `Pipeline.presence`. The
  view keeps both; only the back wakes the brain, with the break's band
  (`Band.away`).
- **Headless**: `{"dev":"presence","signal":…}` and `{"dev":"presence",
  "idle_ms":N}` stand in for the Mac. [harness/HARNESS.md](../../harness/HARNESS.md) §9.
- **Steering**: boop's Example for a very long break (happy, glad in a
  sound, twice), chatter's for a short one (excited, glad in a sound);
  a personality's budget goes from 700 to 750. Rebased onto the voice
  on the card (`f0b9fb1c`), so the Examples use `say.feeling`'s words.
- **Evals**: steps `away` and `back`, and scenarios `63`–`65`.

## What ran

1. `make -C internal test` (with `BOOP_JEV_KEY` unset, which
   `testJevsKeyIsReadOffHome` needs): 321 passed after the first rebase,
   and 357 after the second, onto the overnight pass (`cb52d413`); 9 of
   them are new, in `PresenceTests` and `PresenceRuntimeTests`. The
   headless run (3) and the evals on `63`–`65` (4) passed again after
   it, with the same greetings.
2. `make build`: the app, with `PresenceSignals`, builds.
3. `Boop --headless --brain scripted --debug` driven over its socket:
   idle 2 minutes, a lock, 31 s, 2 hours, an unlock, a touch. The
   transcript got:

   ```jsonl
   {"seq":1,"ts":1790668176722,"source":"mac","type":"presence","phase":"start","specific_type":"locked","data":{"since":1790668056722}}
   {"seq":2,"ts":1790675379108,"source":"mac","type":"presence","phase":"end","specific_type":"unlocked","data":{}}
   ```

   and `debug.jsonl` the view events `You stepped away from the Mac.`
   (no pass) and `You came back to the Mac after a very long break.`
   (`away` `very long`), which woke the one pass of the run.
4. `boopdev eval` on `63`–`65` with Jev, one run each, 19 requests,
   twice. Both 3/3.

   Before the rebase, on the 40-take bank, every greeting was "Heh...":
   the only happy take that isn't for a success. After it, on the 2,722
   takes, a happy face has nine glad takes outside a finish, and Voice
   picks among them (median latency 266 ms):

   | Scenario | At | NOW | Boop |
   | --- | --- | --- | --- |
   | `63` | 3h | You came back to the Mac after a very long break. | happy, "Eep!", twice; mood happy |
   | `64` | 10m | You came back to the Mac after a short break. | happy, "Eep!", twice; mood stays calm |
   | `65` | 30m | claude finished turn 1 on "landing": done, a very long turn, 1 tool call. | excited, a success, "Big tiny win", three times |
   | `65` | 1h30m | You came back to the Mac after a long break. | happy, "Heh...", twice; no finish |

5. `make eval` after the rebase (654 requests): 56/60, with `20` the
   known gap. The three others, rerun with main's steering files (this
   branch's code, without its two Examples):

   | Scenario | This branch | Main's steering | What fails |
   | --- | --- | --- | --- |
   | `40` garbled talk | 2/3 | 2/3 | a filler gets no face |
   | `52` routine work (chatter) | 0/1 | 0/1 | calm drifts to engaged at routine commands |
   | `15` quiet work | 1/9 (1 + 3 + 5 runs) | 5/8 (3 + 5 runs) | a determined face says "upset" ("Failed Nnh", "Oops Ngh") at a check-in |

   `40` and `52` fail as often without this branch: they came with the
   voice on the card. `15` fails more often with boop's new Example
   than without it, the same failure either way.

## What's left

- `15`: boop's Example of coming back seems to make an upset word at a
  working check-in likelier. Not yet tried: `15` and `63`–`65` without
  the Example.
- The menu-bar app's real signals haven't been checked on the Mac: that
  takes the owner running `make run`, locking the screen for over 30 s
  and unlocking it, then reading `boop.log` for `presence: away
  (locked)` and `presence: back (unlocked)`.
- `64` shows Boop still smiles at a short break. The mood holds, which is
  what the scenario asks; whether a short break should get no face at
  all is the owner's call.
