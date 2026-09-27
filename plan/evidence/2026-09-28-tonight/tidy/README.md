# Tidy: `state` without `idle` and `wait` (2026-09-28)

The overnight run's tidy lane. It closes PLAN.md §3's "`state`'s `idle`
and `wait` are only the dashboard's".

## What changed

- **The wire.** `StateSnapshot` has no `idle` or `wait`, so the `state`
  line is `base`, `mood`, `attn`, `busy` and `vol`
  ([PROTOCOL.md](../../../PROTOCOL.md) §3). The firmware never parsed
  either (`device.cpp` reads `base`, `mood`, `attn`, `busy`, `vol`), so
  it's unchanged.
- **The Mac.** The popover's headline and the menu-bar face count the
  waiting from `attn` (`StateSnapshot.waiting`, 1 + `attn.more` or 0).
- **The dashboard can do without them.** Its `base` fact takes busy from
  the `state`, idle from the latest `status` line's sessions and waiting
  from `attn`; the timeline shows a `state` as sent
  (`→ state idle happy · busy 0 · needs you: codex landing · vol 6`,
  with `+N` for more). Preview's lines drop them too
  ([DASHBOARD.md](../../../DASHBOARD.md) §2–3).
- **What the idle count was quietly doing.** The core published only
  when the snapshot changed, and the runtime refreshed the popover and
  wrote `debug.jsonl`'s `status` only then. So the idle count was what
  made a second idle session starting or ending show. Without it, that
  change would have been missed. The core now also watches the session
  list and returns a new `sessions` effect when the list changes and
  the snapshot doesn't ([ARCHITECTURE.md](../../../ARCHITECTURE.md)
  §3.2, and a decision-log row). A core test
  (`testASessionListChangeTheSnapshotDoesntShow`) and a runtime test
  (`testASecondIdleSessionReachesTheStatusNotTheDevice`) pin it. With
  the core's branch disabled, the core test fails; with the runtime's
  handling disabled, the runtime test fails.
- **Other senders.** The firmware scenarios (22 `state` lines in 5
  files), `boopctl soak`, the calm snapshots after it, and the webcam
  clips stop sending `idle` and `wait`. VERIFICATION.md's scenario
  excerpt follows. The dashboard fixture's 16 `state` lines lost the two
  fields in place, checked field by field to be otherwise identical.
  PLAN.md's open item about re-recording that fixture still stands.
- **Nearby dead bits.** The firmware's device tests sent `"ttl":5` on 7
  moments, a field the protocol dropped earlier. They no longer do, and
  one line keeps it beside the old `size` to show that old fields are
  ignored.

## Checks that ran

| Check | Result |
| --- | --- |
| `make build` | Build complete |
| `make -C internal test` | 207 passed, 0 skipped (205 before, plus the two new tests) |
| `make -C internal fw-test` | 111 test cases, 111 succeeded |
| `make -C internal sim` | 11 scenarios, 0 expect failures, 0 new or changed pictures |
| `internal/tools/.venv/bin/python -m unittest discover -s internal/tools/boopctl_lib/tests` | 28 tests OK (27 before, plus one for the counts) |
| `python3 -m unittest discover -s internal/tools/webcam/tests` | 3 tests OK |
| `internal/tools/.venv/bin/python internal/tools/facegen/facegen.py --check` | 337 frames of 30 scenes match Chrome; no generated file changed |
| `.build/debug/Boop --snapshots DIR` | All panes rendered. The crowded overview still reads "Needs you", with the needs-you face |
| Mutation: the core's `sessions` branch off | `testASessionListChangeTheSnapshotDoesntShow` fails |
| Mutation: the runtime ignores `sessions` | `testASecondIdleSessionReachesTheStatusNotTheDevice` fails |

No board, Bluetooth, webcam or Jev was used.

## The headless run

This build ran as `Boop --headless --state-dir /tmp/tdy --brain scripted
--name Pip --debug`. `boopdev replay` sent it
`internal/app/Tests/Fixtures/hooks/codex/synthetic/approval-asked.jsonl`
(`--agent codex`), then two Claude `SessionStart`s (`notes`, `jetpack`)
and `jetpack`'s `SessionEnd`, 0.5 s apart. These are the `state` lines
it sent, from `debug.jsonl`. The fourth is PROTOCOL.md §3's example:

```
{"t":"state","v":1,"base":"asleep","mood":"happy","busy":0,"vol":6}
{"t":"state","v":1,"base":"idle","mood":"happy","busy":0,"vol":6}
{"t":"state","v":1,"base":"working","mood":"happy","busy":1,"vol":6}
{"t":"state","v":1,"base":"idle","mood":"happy","attn":{"agent":"codex","project":"landing","more":0},"busy":0,"vol":6}
{"t":"state","v":1,"base":"working","mood":"happy","busy":1,"vol":6}
{"t":"state","v":1,"base":"working","mood":"happy","busy":1,"vol":6}   (10 s keepalives)
{"t":"state","v":1,"base":"working","mood":"happy","busy":1,"vol":6}
{"t":"state","v":1,"base":"working","mood":"happy","busy":1,"vol":6}
{"t":"state","v":1,"base":"idle","mood":"happy","busy":0,"vol":6}
```

The extra sessions sent no `state`, but each wrote a `status` line
(session lists shortened):

```
{"status":{…,"sessions":[codex landing idle, claude notes idle]}}
{"status":{…,"sessions":[codex landing idle, claude notes idle, claude jetpack idle]}}
{"status":{…,"sessions":[codex landing idle, claude notes idle]}}
```

The dashboard's feed (`Board`) on that `debug.jsonl` ended with
`base` = `idle · busy 0 · idle 2 · waiting 0`. At the needs-you `state`
it showed `idle · busy 0 · idle 0 · waiting 1` and `needs you` =
`codex · landing`.

## Decisions

- **`waiting` stays on the Mac as a computed property.** The popover
  says "*N* sessions need you". The count is `attn`'s, so it's derived
  rather than stored or sent.
- **A new `sessions` effect, not a second `state`.** Returning `.state`
  with an unchanged snapshot would break that effect's contract ("only
  when something on it changed"), and `boopdev replay --states` would
  print duplicate lines. The runtime handles `sessions` like `state` for
  the popover and the `status` line, and doesn't print it in debug
  mode, since the `status` line shows the change.
- **The fixture was edited, not re-recorded.** Re-recording it would
  change most of `test_dash.py`'s pinned rows. PLAN.md already has that
  as an open item, which other work may be taking up.

## Proposals

- Re-record `tests/fixtures/headless-debug.jsonl` (PLAN.md §3's open
  item). That would bring in started actions, settles, loops and the
  new `state` shape in one go.
- `make -C internal sim` writes to a fixed `/tmp/boop-sim`, which
  parallel worktrees share (left as a breadcrumb). It could be keyed
  by checkout.

## An independent check

A second pass over this branch, after the commits above.

**Nothing reads `idle` or `wait` any more.** A grep of the Mac app,
the firmware (`device.cpp` reads `base`, `mood`, `attn`, `busy` and
`vol`), `boopctl` (soak, the webcam clips, `show_state`, the dashboard),
the e2e steps (they match `dbg.state`, which has neither), the
scenarios, the fixtures, the skills, the READMEs and `plan/` found only
`base` values of `idle` and the 2026-09-27 decision-log row, which is
history. The fixture's 16 edited lines lost exactly `idle` and `wait`,
each `wait` was 1 + `attn.more`, and each old `idle` equals the idle
count in the `status` line that follows it.

**The counts on a busier run.** A headless app (`--brain scripted
--link none --debug`, state in `/tmp`) took
[check/four-sessions.jsonl](check/four-sessions.jsonl) through
`boopdev replay --socket`: four Claude sessions, two of them asking at
once, then turns ending and one session leaving. The dashboard's
`Board` on its `debug.jsonl`, each fact once it settled:

| After | `base` | `needs you` |
| --- | --- | --- |
| Three sessions start | `idle · busy 0 · idle 3 · waiting 0` | no |
| gamma, then alpha, work | `working · busy 2 · idle 1 · waiting 0` | no |
| alpha asks | `working · busy 1 · idle 1 · waiting 1` | `claude · alpha` |
| delta starts, works and asks | `working · busy 1 · idle 1 · waiting 2` | `claude · alpha (+1)` |
| alpha's tool finishes | `working · busy 2 · idle 1 · waiting 1` | `claude · delta` |
| alpha and gamma stop | `idle · busy 0 · idle 3 · waiting 1` | `claude · delta` |
| beta ends | `idle · busy 0 · idle 2 · waiting 1` | `claude · delta` |

beta's and gamma's starts, delta's start and beta's end sent no
`state` and each wrote a `status` line. Between a `state` and the
`status` right after it, `base` can mix the new busy count with the old
idle one for the few microseconds between the two writes. The dashboard
applies each read's lines before it draws, every 0.25 s, so that isn't
worth a change.

**Mutations again.** With the runtime ignoring `sessions`,
`testASecondIdleSessionReachesTheStatusNotTheDevice` fails; with the
core's `sessions` branch gone, `testASessionListChangeTheSnapshotDoesntShow`
fails. Both were restored and rebuilt before the checks below.

**Checks that ran:** `make build`; `make -C internal test` (207
passed); `make -C internal fw-test` (111/111); `make -C internal sim`
(11 scenarios, 0 expect failures, 0 changed pictures); the boopctl
tests (28 OK); the webcam tests (3 OK); `facegen.py --check` (337
frames match); `Boop --snapshots` (the crowded overview says "Needs
you").

**Fixed here:** CoreTests' comment on the `state` shape still said it
carries "the counts", and DASHBOARD.md §7's sentence about the edited
fixture didn't parse.
