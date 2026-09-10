# Product specs

Start with [Component behaviors](BEHAVIORS.md): the compact reference for what
Boop does, what triggers it, the current numbers, and what we can tweak.

| Read next | Purpose |
| --- | --- |
| [Vision](VISION.md) | Product intent and personality |
| [Device](UX-DEVICE.md) · [Mac app](UX-APP.md) | Screen, motion, button and navigation details |
| [Help](UX-HELP.md) | The nudge ladder and request dismissal |
| [Growth](UX-GROWTH.md) · [XP formula](XP-AND-SKILL-TREE.md) | Awards, levels, streaks and personality |
| [Voice](UX-VOICE.md) | Markdown-guided dialogue, personality and memory |
| [Architecture](ARCHITECTURE.md) · [Wire](WIRE-V2.md) | Ownership, storage, budgets and protocol |
| [Implementation plan](PLAN.md) · [Verification](VERIFICATION.md) | Work status, evidence and remaining gates |
| [Ideas](IDEAS.md) | Possibilities, not promised behavior |

## Keeping this current

For a behavior change, edit the matching row in `BEHAVIORS.md` and its detailed
UX spec in the same change as the implementation. Update architecture or wire
specs when their contracts change, and verification when the check changes.
Use `PLAN.md` for delivery status; a source inspection does not close a live
device or harness gate.

The catalog separates **current behavior**, **target**, and **gap**. An observed
implementation discrepancy is not an approved product decision. Resolve it by
changing the implementation or explicitly revising the target; do not leave
two competing rules or rely on a newer note at the bottom of a document.
