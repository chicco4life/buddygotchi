# Two-stage brain — 2026-09-26

The brain's pipeline as built (HARNESS.md): four inputs, a classifier that
decides, a writer that writes only the words, and one append-only
transcript. L5 on the 50 fixture inputs (`app/Tests/Fixtures/inputs/`), 3
minutes apart, sharing one transcript, one run per classifier, both
writing with Apple's model (`apple:27.0`).

| Run | Result | Refused | Stage 1 on the menu | Writer: slots filled | Dropped by actions | p95 agent finished / you said |
| --- | --- | --- | --- | --- | --- | --- |
| if-else + Apple ([run](l5-rules-apple.txt)) | PASS | 0/50 | 50/50 | 36/36, none failed | 1 of 44 (a note already there) | 2.7 / 2.3 s |
| Jev + Apple ([run](l5-jev-apple.txt)) | PASS | 0/50 | 50/50 | 31/31, none failed | 1 of 43 (a note already there) | 2.5 / 2.8 s |

Jev's own step took about 0.25 s (p50); Apple's writing about 1.9 s. Every
input kind stayed inside its deadline. Every input, side by side:
[side-by-side.md](side-by-side.md).

What the sample shows:

- **Asking for quiet works with both.** "Shut up for an hour" → `quiet(60)`
  and a silent sulk; "keep it down for fifteen minutes" → `quiet(15)`. Jev
  also took "stop talking for a bit" as 15 minutes.
- **Notes are what was said.** "Remember the demo is on Thursday" → "demo on
  Thursday"; "note that standup moved to half ten" → "standup moved to half
  ten". Things the sample memory already had are refused by the store.
- **Jev reacts more, and more aptly.** A silent face on most agent starts,
  sleepy at 23:48; "time for lunch" → hopeful, "food"; "that was a long
  one" → proud, "finally". It stays quiet on quick finishes. It once
  mumbled annoyed at an 18-minute test run that finished fine.
- **The if-else classifier is predictable**, as intended: proud "finally"
  for every long finish, annoyed for every failure, curious "hmm" for
  anything it has no row for.
- **Apple's model as writer has no refusals**, where deciding everything it
  refused 2 of 54 and answered with silence most of the time ([Jev
  evidence](../2026-09-26-jev-brain/README.md)).
- **New day.** The if-else classifier leaves long-term memory alone. Jev
  kept one line in four runs ("quiet before 10am", a preference close to one
  the sample already has).

Found and fixed while running it (before these runs):

- With a rule "remember about you when yesterday had notes", Apple's model
  wrote lines like "frazzled." It has no way to decline a slot it's given,
  so the if-else classifier no longer remembers anything on a new day.
- For "remember the demo is on Thursday" Apple's model once wrote "tests
  failed again", pulled from memory's Happened lines. Its request now ends
  with what just happened, what was said and what Boop decided.
- The if-else classifier answered greetings and praise with "curious"; it
  has rows for them now, matched on whole words.

The JSONL logs (fixture memory and inputs, both stages' answers) stayed in
the session's scratch directory.

Not run: the app with Bluetooth and a live talk, which is the owner's.
