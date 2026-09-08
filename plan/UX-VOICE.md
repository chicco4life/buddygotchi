# UX: Voice

Status: first draft, 2026-09-09, written by the agent to unblock Phase 5 while
the owner was away. Style choices are assumptions to overturn. Refines
`VISION.md` §9 and `IDEAS.md` idea 1.

## What the voice is for

One short line at the right moment, in the buddy's own character: greets,
cheers with a story, uh-oh remarks, the end-of-day recap, and the nightly
profile lines. It never explains, never instructs, never judges the owner.

## Style guide

- Lowercase, no exclamation marks except in a dance line. One sentence on the
  device (≤ 40 bytes), up to three in the app.
- Specific beats generic: name the runner, the project, the count.
- Sass aims at the agent or the world. Never a second-person negative about
  the owner ("you keep…" is banned; "that file again" is fine).
- No emoji on the device; at most one in the app.
- Never mention tokens, money, or productivity.

## Sass ceiling

Cheek trait 0–255 → three registers: earnest (< 96), wry (96–191), cheeky
(≥ 192). Cheeky may tease the agent by name ("codex tried that already").
Earnest never teases. The register is chosen per line, never per word.

## Inputs to a line

Moment kind and facts; up to three profile lines; traits; agent name;
time-of-day bucket (morning, day, evening, late); language. Never raw text.

## Authored banks (the floor)

Per language, per moment kind, per register: ≥ 8 distinct authored bases each. Selection is
seeded by (moment, day) so the same day does not repeat a line, and the last
20 lines used are excluded. Optional seeded lead-ins live separately and appear
on at most 40% of draws; they are seasoning, not authored content. English and Korean ship; Korean lines are
written, not translated.

## Model

A local model behind a `VoiceRuntime` protocol. Default implementation: Apple
Foundation Models on macOS 26 when available, else a bundled small model
through a llama.cpp-style runtime is out of scope for this phase (stub that
returns nil). Budget 1 s for a device line; past budget the authored line is
used and the model result is discarded. The model's output is validated by
the same post-filter as authored lines (length, banned patterns, second
person negative).

## Recap

End of day, one paragraph in the app and one line on the device: turns,
tasks, biggest moment, what is still open. Built from facts only.

## Reflection (nightly)

Rules from `UX-GROWTH.md` produce candidate profile lines; when the model
is available it may rephrase candidates into the buddy's voice but may not
invent new facts. Max 5 lines a night.
