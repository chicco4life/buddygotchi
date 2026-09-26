# Boop spec

These documents are the contract for Boop v1. The code implements them, and
a change to one goes in the same commit as the code
([CLAUDE.md](../CLAUDE.md)).

| Read | For |
| --- | --- |
| [VISION.md](VISION.md) | Why Boop exists, personality first, the promises, scope |
| [UX.md](UX.md) | The screens, controls, setup and the Mac app |
| [BEHAVIORS.md](BEHAVIORS.md) | What Boop does when things happen; XP, hunger, mood, sound and light |
| [VOICE.md](VOICE.md) | The gibberish: how it's built, checked and played |
| [ARCHITECTURE.md](ARCHITECTURE.md) | The parts and their boundaries, the memory files, and the decisions (§11) |
| [ADAPTERS.md](ADAPTERS.md) | Hooks, event mapping, and "needs you" |
| [HARNESS.md](HARNESS.md) | The generic harness and the brain's two stages: a classifier that decides, and a writer for the words |
| [steering.md](steering.md) | The brain's read-only instructions (shipped in the app) |
| [PROTOCOL.md](PROTOCOL.md) | The messages between the Mac and the device, over Bluetooth or USB |
| [DEVICE.md](DEVICE.md) | The board, pins, firmware stack and bring-up |
| [VERIFICATION.md](VERIFICATION.md) | How everything is checked, including the screen |
| [EVALS.md](EVALS.md) | The harness eval scenarios: how they run and what each checks |
| [PLAN.md](PLAN.md) | The build order, the check for each milestone, how the build runs, the morning checklist, and the open items |
| [LOOP.md](LOOP.md) | The prompt for one iteration of the unattended build |
| [FUTURE.md](FUTURE.md) | Ideas we like but aren't building in v1 |

The previous generation's specs are in
[archived/plan-gen2/](../archived/plan-gen2/).
