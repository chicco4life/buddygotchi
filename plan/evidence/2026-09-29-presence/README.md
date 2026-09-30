# Here and away

2026-09-29. The owner's brief: Boop should know when you step away from
the Mac and come back, with the deciding kept in the trigger, out of the
harness, the view and the core. Only coming back does anything; a wrong
away (a long video) must never make Boop go quiet.

## What changed

- **The detector** (`app/BoopKit/Presence/PresenceDetector.swift`) is the
  only code that decides. Away after a 10-minute lock or sleep (30 s
  until 2026-09-30), or 30 minutes
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
  takes the owner running `make run`, locking the screen for over 10 minutes
  and unlocking it, then reading `boop.log` for `presence: away
  (locked)` and `presence: back (unlocked)`.
- `64` shows Boop still smiles at a short break. The mood holds, which is
  what the scenario asks; whether a short break should get no face at
  all is the owner's call.

## 2026-09-30: no hello after a minute

The owner: coming back should get a cheer, but not after a minute away;
after ten minutes is right. So the detector counts a lock or sleep as
an away only after 10 minutes (`lockAwayMs`, was 30 s); a shorter one
records nothing, so there's nothing to greet. `PresenceTests` pins a
minute's lock, one just under 10 minutes and a 9-minute sleep as
nothing, and 10 minutes as an away.

`64` is now "back after ten minutes gets a cheer", and `63` and `64`
are `always`; every back step expects a glad feeling. With Jev:

| Scenario | Runs | Boop |
| --- | --- | --- |
| `63` back after 3 hours | 5/5 | happy, "Eep!", twice |
| `64` back after 10 minutes | 5/5 | happy, "Eep!", twice; mood stays calm |
| `65` back after work finished while away | 1/1 | happy, "Hehehe...", twice |

Every run says "Eep!" at the first greeting because each eval run is a
fresh launch and `ReactAction` seeds its take picks with a fixed
number; in the app the picks move on with every reaction.

The full `make eval` before this change, on main at `4d479011`: 54/60,
with `20` the known gap and none of the failures about coming back
(`13`, `15`, `24`, `40`, `52`).


## 2026-09-30: a hello, not just "Eep!"

The owner wanted something more concrete than a glad sound. The bank had
greetings Boop never said: Hello, Hey and Hello hello, recorded for needs
you (which never says them), and Hi, Howdy, Salut, Oh hello and Hey hey,
recorded for pokes. Voicegen now files these 62 takes under a new
`say.about` topic, `hello` (four or more in every face); the pack's
version stays `1aace295d219`, so the card doesn't change. boop's
Example is now "happy, glad in a sound, then hello, twice".

`make -C internal test`: 358 passed (`testEveryFaceCanSayHello` new).
With Jev:

| Scenario | Runs | Boop |
| --- | --- | --- |
| `63` back after 3 hours | 5/5 | happy, "Eep! Howdy", twice |
| `64` back after 10 minutes | 5/5 | happy, "Eep! Howdy", twice; mood stays calm |
| `65` back after work finished while away | 1/1 | happy, "Mwahaha... Howdy", twice |
| `05`, `16`, `35`, `49` (pokes and talk) | 1/1 each | pokes say "Whoa", "Aww...", "Argh", never a greeting |
