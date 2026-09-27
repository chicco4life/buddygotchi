# Boop spec

Updated 2026-09-27. The index of Boop v1's specs. They're the contract the
code implements, so a change to one goes in the same commit as the code
([CLAUDE.md](../CLAUDE.md) says which spec goes with which code). Start
with the vision.

| Read | For |
| --- | --- |
| [VISION.md](VISION.md) | Why Boop exists, its personality, the promises, and what's in v1 |
| [BEHAVIORS.md](BEHAVIORS.md) | What Boop does when things happen, with its sound and light, and how each personality changes it |
| [UX.md](UX.md) | The screens, controls, setup and the Mac app |
| [VOICE.md](VOICE.md) | The gibberish: how it's built, checked and played |
| [ARCHITECTURE.md](ARCHITECTURE.md) | The parts and their boundaries, the data flow, queues and timers, what Boop keeps on disk, budgets, and the decisions in force |
| [ADAPTERS.md](ADAPTERS.md) | The hook client, the event each hook becomes, session states and "needs you", and installing the hooks |
| [harness/HARNESS.md](harness/HARNESS.md) | The harness: how an event becomes a question for Jev and an answer becomes an action; the transcript and the state |
| [harness/EVENTS.md](harness/EVENTS.md) | The seven kinds of event the core hands the harness: their facts, lines and rule reactions, and which wake the brain |
| [harness/DECISIONS.md](harness/DECISIONS.md) | What Boop decides: the steering files, the questions, how answers are read, and the actions |
| [harness/EXAMPLE.md](harness/EXAMPLE.md) | One turn of failing tests end to end, from a real eval run: events, transcript, state, Jev's answers and what Boop does |
| [steering/](steering/guide.md) | The guide, personalities and moods Jev reads, read-only and bundled in the app ([harness/DECISIONS.md](harness/DECISIONS.md) §2) |
| [PROTOCOL.md](PROTOCOL.md) | The messages between the Mac and the device, over Bluetooth or USB, and the debug messages over USB |
| [DEVICE.md](DEVICE.md) | The board, pins, firmware stack, what the device keeps, and building and flashing |
| [VERIFICATION.md](VERIFICATION.md) | How everything is checked (L0–L6), and every tool |
| [DASHBOARD.md](DASHBOARD.md) | `boopctl dash`: Boop's state, face, passes and timeline live, and keys that force a mood, a reaction or an animation |
| [EVALS.md](EVALS.md) | The harness eval scenarios: how they run and what each checks |
| [PLAN.md](PLAN.md) | Where things stand: milestones, owner checks, open items |
| [FUTURE.md](FUTURE.md) | What v1 parked, and ideas we like but aren't building yet |

What each check found is in [evidence/](evidence/), one folder per piece
of work. History lives in `archived/`: the finished v1 build plan and its
full decision log in [archived/plan-v1-build/](../archived/plan-v1-build/),
and the previous generation's specs in
[archived/plan-gen2/](../archived/plan-gen2/).
