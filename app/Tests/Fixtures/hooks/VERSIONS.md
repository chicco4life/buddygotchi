# Hook fixture matrix

Each directory under `hooks/<agent>/<capture-date>/` holds raw hook payloads
recorded by `app/tools/record-hooks.sh` from that agent's release on that day.
`HookFixtureTests` replays every file; a new agent release gets a new dated
directory before we claim support for it (see `plan/VERIFICATION.md` §4).

| Agent | Release captured | Capture date | Doctor run (from that harness) |
| --- | --- | --- | --- |
| Claude Code | 2.1.263 | 2026-09-08 | 2026-09-09: static 8/8, live check fired (installed hook v4 pending repair) |
| Codex CLI | 0.153.4 | 2026-09-08 | 2026-09-09: static checks via delegate sandbox; live check needs a person in Codex |
| Cursor | not recorded (Cursor.app not installed on the capture Mac) | 2026-09-08 | pending: run `skills/doctor/doctor.sh` from a Cursor chat |

To refresh a row: install the agent release, launch Boop, run
`app/tools/record-hooks.sh <agent>` as the hook target for one short session,
then run the doctor from inside that harness and note the result here.
