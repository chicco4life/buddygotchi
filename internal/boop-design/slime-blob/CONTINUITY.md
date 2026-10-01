# Continuous actor and animation authoring

Updated 2026-10-02. Implementation plan around the current audition, not
an assertion that state scenes or production scheduling already exist.

## Keep the object; change its targets

The current [preview/slime.js](preview/slime.js) generates a dome mesh and
deforms it analytically. It shades blue translucent gel and a soft rim,
then applies low-resolution bloom. There is no inner jellyfish cap or
model asset. `paintFace` draws pupil-free rounded eyes/mouth/cheeks/tears
to a scratch Canvas texture; the renderer attaches it to the body using
rest-surface coordinates. Do not make the face slide independently during
a grab or body deformation.

Source areas to inspect:

| Area | Current responsibility | How to extend |
| --- | --- | --- |
| `profiles`, `paintFace` | Face designs from expressions.json | Edit catalogue + a matching painter primitive; rebuild catalog.js |
| `advance`, `pose`, `impulse` | Accepted V1 springs/blink/gaze | Preserve seven locked blocks; add channels outside them |
| `perform`, `actorChannels`, `composePose`, `posture` | Additive authored emotion acting | Add bounded activity layer without replacing base pose |
| `createGL`, `shape`, material fragment and bloom | Persistent body + gel appearance | Keep silhouette/material identity; don't change them per mood |
| `startGrab`, `moveGrab`, `releaseGrab` | Local pull, pointer capture, rebound | Retain bounded spring state; explicitly handle host termination |
| `createFallback` | Lower-cost Canvas approximation | Preserve expression/interaction semantics; not identical 3D material |

The accepted numbers and source blocks live only in
[contracts/motion-v1.json](contracts/motion-v1.json). The hash validator
protects their exact JS/GLSL code, not all mutable art around it. Changed
physics require an explicitly named reviewed motion revision. The
surface-drag/acting extensions are later review candidates, not silently
part of the accepted V1 lock.

## Proposed layer ownership

One monotonic presentation clock drives all layers and sound cue IDs:

```
authoritative host facts ──> state target ──> activity/props ──┐
validated mood edge ──────> face + emotion acting ────────────┤
local touch/poke ─────────> bounded pull/impulses ────────────┼─> ONE body
continuous V1 springs/blink/breath/gaze ──────────────────────┘     │
actual contact/card-reveal cues ──> sparse procedural SFX ──────────┘
```

Preserve current displacement and velocity when changing any target.
Use smooth face weights and softened control interpolation. The present
face-weight method blends rendered face silhouettes; extreme transitions
can briefly look doubled. Review all edges and, where necessary, replace
that with semantic eye/mouth control interpolation or a short blink bridge
**outside locked code**, reviewed as a new face-transition layer. Do not
hide it with a whole-character fade/reset.

Suggested composition order: base shape → mood posture → activity pose →
gesture impulses → local grab → final bounds. There must be one owner of
each channel: a drag owns the grabbed patch, activity owns keyboard
contact, mood owns face style, and attention owns priority. Blend
additive offsets; cap the combined result, not each layer in isolation.
Make suppression explicit so angry+typing+drag cannot exceed the body's
safe envelope or produce competing repeated impacts.

## States share one scene

Build a persistent desk and computer once. Working, terminal, searching,
analyzing, testing, planning and generic tool use are activity submodes,
not swaps to unrelated sets. Keep desk positions and parent transforms
stable, change screen cue/cards and contact choreography. Waiting simply
pauses the work action. Helper blobs enter alongside the hero, never
replace it. Every state in [state-plan.json](state-plan.json) still has
its own meaning, variations and audio policy.

An action recipe has phases `enter → act → recover → sustain`. Start
from the current pose, blend in, perform its contacts, recover toward the
current state target, and sustain. A state change cancels future contacts
from the old recipe but leaves physical velocities alive. Bridge from
current controls, not from a hard-coded neutral first frame. A loopable
authored offset starts/ends at zero offset and compatible derivative;
the continuing physical body need not return to a frozen identical frame.

Never reset face/mood when terminal becomes searching. Never destroy the
desk between work variations. A completion reveal may raise a card in
front of the same hero; after the one-shot, return toward the **latest**
host snapshot, not a stale state saved before the animation.

## A transition for every directed mood edge

[transitions.json](transitions.json) is generated from actual adjacency,
with an entry for each permitted directed edge. Each entry specifies a
composable target-face/posture retarget plus three proposed bridge styles.
It is a work checklist, not executed policy. Direction/category matters:
frightened→angry is not the same acting motivation as angry→frightened.

Ordinary bridges gently gather and settle. Dramatic bridges may recoil
or briefly compress before retargeting; their permission comes from host
evidence, never their theatrical animation. At rest suppress gestures;
with a grab held, retarget the face while deferring conflicting impulses;
with an alert active, preserve its card and recognition cue. Shared
bridge primitives can cover many edges, but every edge still needs a
readability/continuity review. They do not require separate video files.

## Variability, without chaos

Use a deterministic seed for replay/tests and a per-actor seeded PRNG in
normal runs. First pick an authored variation compatible with state/mood
and host outcome/context, excluding the most recently used. Then choose
bounded microparameters: a small gaze offset, pause length, number of
typing contacts or side of a lean. Make variability visible in action
rhythm, not only random tint/volume. Clamp inputs; an LLM cannot add a
limb, change physics, execute JS or invent a successful result.

The audition already has authored recipe cues and quiet auto intervals.
Production should add a shuffle bag/short history per mood+state, avoid
immediate repeats, and use safe recovery boundaries for variant changes.
Ten minutes of work can vary silently without ten minutes of sound.
Whole-state completion and alerts are event-gated one-shots, not periodic
random surprises. No per-frame LLM/API call is required.

## Alerts, taps and interruption

Use the repo's existing LinkKit turn/attention semantics, not an invented
priority scheduler that delays needs_you. A new request starts the upper
alert once, with broad surface knocks followed by the invariant ding;
then its sign holds silently. Mood may change expression/knock character
but not restart an already-consumed notification sound. Preserve the
bottom text lane and do not obscure the prompt with long acting.

Poke can add an impulse immediately while the engine retains factual
state. If the current alert/finish tap opens a thread, honor that existing
behavior; it still never grants permission. Surface drag is a separate
interaction. The audition cycles faces on a quick tap solely for review;
do not copy that into production graph logic.

A production desktop container must terminate grabs on pointerup,
pointercancel, lost capture, visibility/focus loss and host boundary exit.
The embedded-preview guards cannot guarantee delivery of events outside
a browser iframe. The standalone preview removes that embedding boundary,
but OS/window-boundary and hardware-touch behavior still need testing.

## Proposed renderer adapter, not a new wire schema

Keep the existing primary controls. A future desktop adapter can translate
Boop's validated snapshots/moments to target mood/state, plus factual
outcome/context, then advance locally each frame. State and motion data
never need to be generated by Jev. Queued one-shots must retain request
identity and lifecycle so played/cut/skipped is logged correctly.

Before integrating, implement and test this adapter in Boop-specific code;
do not place slime or mood logic in the generic agent-hooks/JHarness/
LinkKit packages. No adapter is provided by the audition API. The preview's
`setEmotion`, `poke`, `shake`, `perform` and `getState` are local tools for
review; they are not permission to send unsupported 42-mood wire IDs.

## Desktop first; embedded is a separate renderer decision

Disk size is not device runtime cost. The WebGL mesh, scratch RGBA face
texture, full scene targets and bloom require capabilities/memory the
original ESP32 does not have. Options to investigate later are an
analytical native 2.5D gel renderer with low-cost highlights, or a measured
alternative display/host-render path. Do not assume the existing control
link can stream video or that facegen converts this shader automatically.
Keep the host mood/state interface renderer-independent and measure actual
board RAM, frame time, display bandwidth and audio headroom before choosing.
