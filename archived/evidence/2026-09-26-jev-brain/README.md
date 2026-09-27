# System-one brain (Jev) — 2026-09-26

L5 on the 54 fixture triggers, 3 minutes apart, `--history 4`, one run per
brain, after the typed brain contract (PLAN.md A7). Jev is `jev-latest`
(the API reported `jev-1.13.0`); its writer is Apple's model (`apple:27.0`).

| Brain | Result | Refused | Valid shape | Quiet | Spoke on event / tap / talk | Dropped by actions | Latency p50 event / tap / talk |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Jev ([run](l5-jev.txt)) | FAIL (drops 3/45, all reflection written by Apple's model) | 0/54 | 54/54 | 14/54 | 1/24 · 2/8 · 11/18 | 3 | 0.22 · 0.21 · 0.22 s |
| Apple ([run](l5-apple.txt)) | FAIL (drops 2/24) | 2/54 | 52/52 | 33/52 | 0/23 · 0/8 · 0/17 | 2 (and 10 past a limit) | 1.99 · 1.86 · 1.88 s |
| Rules ([run](l5-rules.txt)) | PASS | 0/54 | 54/54 | 19/54 | 2/24 · 2/8 · 16/18 | 0 | 0 ms |

Every trigger, side by side, with Jev's top `act` and its `note` score:
[side-by-side.md](side-by-side.md).

What stands out:

- **Talk requests land.** "Shut up for an hour" → `quiet(60)`, "keep it
  down for fifteen minutes" → `quiet(15)`, "stop talking for a bit" →
  `quiet(30)`. Apple's model answered the second with an annoyed mumble
  about tests and the third with nothing.
- **Taps and failures get a reaction, not junk.** A face on every tap (a
  sleepy one at 23:55), `side_eye` on every failed turn, and no notes on
  events. Apple's model stayed quiet on most taps and tried a `note` on 10
  events, which the limit dropped.
- **Notes follow what memory already has.** The three old note requests
  ("remember I ship on Fridays", "jetpack is the payments service", "note
  that landing launches Monday") are all in the sample memory already;
  Jev's yes/no for `note` scored 0.22–0.25 with the memory and 0.93–0.96
  without it. The two new fixtures scored 0.93 and 0.82, and Apple's model
  wrote "demo on Thursday" and "standup moved to half ten".
- **One call per answer.** "Shut up for an hour" gets `quiet(60)` without
  steering's sulky face: Jev picks one `act`.
- **Reflection is Apple's model's.** All three dropped calls are its
  `moment` and `remember` texts (a retold moment, "jetpack = payments" read
  as code). Apple's model on its own drops the same kinds.

How the note question was chosen: as an `act` option, `note` never won
(0.21–0.29 against `stay_quiet` up to 0.70). As its own yes/no it separates
note requests from small talk (0.93 against 0.10 on the new facts), and
first asking the writer to decide again lost both notes, so the writer now
only writes the call Jev chose.

The JSONL logs (prompts from the sample memory, Jev's answers) stayed in
the session's scratch directory.
