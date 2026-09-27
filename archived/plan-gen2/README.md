# Product specs

The evidence these specs link to (`evidence/…`) is no longer in the tree.
Read it at the tag: `git show gen2-final:archived/plan-gen2/evidence/<path>`.

Start with [How Boop behaves](BEHAVIORS.md): the compact reference for what
Boop does, what triggers it, the current numbers, and the differences between the two screens.

| Read next | Purpose |
| --- | --- |
| [Vision](VISION.md) | Product intent and personality |
| [Device](UX-DEVICE.md) · [Mac app](UX-APP.md) | Screen, motion, button and navigation details |
| [Help](UX-HELP.md) | The nudge ladder and request dismissal |
| [Growth](UX-GROWTH.md) · [XP formula](XP-AND-SKILL-TREE.md) | Cumulative XP, turn counts and streaks |
| [Voice](UX-VOICE.md) | Markdown personality, event-based dialogue and memory |
| [Work context](UX-WORK-SCOPE.md) | Shared pipeline, implemented scope slice, planned payoff/callback stages |
| [Architecture](ARCHITECTURE.md) · [Wire](WIRE-V2.md) | Ownership, storage, budgets and protocol |
| [Implementation plan](PLAN.md) · [Verification](VERIFICATION.md) | Work status, evidence and remaining gates |
| [Ideas](IDEAS.md) | Possibilities, not promised behavior |

## Keeping this current

For a behavior change, edit the matching row in `BEHAVIORS.md` and its detailed
UX spec in the same change as the implementation. Update architecture or wire
specs when their contracts change, and verification when the check changes.
Use `PLAN.md` for delivery status; a source inspection does not close a live
device or harness gate.

The behavior guide describes current source; proposals and remaining verification gates are labeled separately. An observed
implementation discrepancy is not an approved product decision. Resolve it by
changing the implementation or explicitly revising the target; do not leave
two competing rules or rely on a newer note at the bottom of a document.
