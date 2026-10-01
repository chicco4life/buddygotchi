# Buddygotchi character animation and jelly slime handover

Updated 2026-10-01. For the designer and engineer creating a separate, full-body, 3D-like slime version of Buddygotchi.

**Build one persistent creature, not a slideshow of creatures.** Reuse Boop's meanings, mood graph, truthful event handling and sound-selection rules. Replace its visual implementation with a continuously animated slime body whose expression, posture, props and jelly motion can change independently. No LLM or video generation belongs in the frame-rendering loop.

This guide separates inspected code from the proposed slime architecture. The SVG review bank, mood graph and recorded voice bank exist. A general character plug-in loader, continuous 3D renderer and production integration of the expanded graph do **not** exist yet. This handover does not implement them.

## Repository and starting point

Repository: [chicco4life/buddygotchi](https://github.com/chicco4life/buddygotchi). Reviewed branch: `codex/boop-mood-spectrum-v4`, source snapshot `2bc6bf645b16d06bf8c3df6b33b0d3b916640fa2`. Counts below describe this snapshot, not a permanently frozen product API. Check the latest branch before implementing.

Read the repository [AGENTS.md](../../../AGENTS.md), [design package guide](../README.md), [architecture](../../../plan/ARCHITECTURE.md) and [verification guide](../../../plan/VERIFICATION.md) first. Preserve the existing pixel character and accepted assets. Work on the new character in a separate internal prototype until reviewed. Do not push, open a PR, merge, deploy or run paid generation without the owner's explicit consent. Do not change enclosure geometry or firmware as an incidental part of the artwork.

## Reference brief

The [shared handover](https://chatgpt.com/space/page_4a8b184328f48191be1934dd225e6474) includes the two downloadable owner-supplied references below. They are references rather than production assets; access follows the shared Space permissions.

- **Blue slime expression sheet** — `codex-clipboard-53f1aed1-dacd-46fa-a13b-f4f3cd6cb155.png`. Use its light-blue palette, broad low dome, rounded lower edge and simple facial readability as inspiration. Make an original face and emotional vocabulary. Do not trace the supplied expressions, white sticker border or highlight pattern. The owner specifically wants a Rimuru-inspired blob, not the identical character.
- **Jelly interaction video** — `96594.MP4`, about 19 seconds. Sampled frames show a purple blob on a watch-sized display during shaking and finger interaction, with changing body silhouette. Use it as a reference for the owner's desired soft jelly response, not as evidence of how that project is implemented. Its engine, source, sensing method and physical simulation are unknown. Do not copy the Ditto face, purple identity, watch UI or third-party assets.

The intended result combines **the blue blob's approachable silhouette with the video's tactile jelly behavior**, while retaining Boop's dramatic personality. It is a whole visible body, not merely eyes inside a screen. It should have a stable floor contact, soft volume, rounded silhouette, restrained gloss and readable eyes. A poke compresses it locally; the opposite side bulges; the body overshoots, wobbles and settles. A second poke adds to the motion already happening rather than restarting a canned wobble from frame zero.

Start with soft, stylized 3D, not expensive photorealism. A small mesh with convincing shading and deformation can communicate jelly without fluid simulation. Test the face on a black background at the actual display size. The new style may use smooth surfaces and rounded tears; the old character's square-particle grammar remains specific to the pixel pack.

## Personality mood activity and performance

These are separate concepts. A new skin must not silently change what an event means or what Boop is allowed to do.

| Concept | Responsibility |
| --- | --- |
| Personality | Long-lived character and reaction preferences. Design direction: overconfident, emotionally transparent, dramatic, easily wounded and secretly needy. Keeps doing the job while performing its feelings. |
| Mood | Persistent emotional condition, such as engaged or grumpy. Changes through the approved graph, not whenever an animation changes. |
| Activity state | What is happening now: terminal, searching, needs_you and so on. Driven by factual context and priority rules. |
| Variation | An alternative performance for that mood and activity. Different actions or props, not only a different speed. |
| Character presentation | Body, face, material, rig, animation and voice identity. This is the layer the slime redesign primarily changes. |

Current production personality files live in [plan/steering](../../../plan/steering/guide.md), with a bundled app copy. They are read-only at runtime. The `chatter` personality is an intentionally talkative debugging configuration, not the desired everyday sound density. The expanded dramatic design direction should be integrated deliberately; artwork does not itself rewrite steering.

Comedy can be exaggerated, but displeasure is aimed at obstacles, not abuse or guilt directed at the human. A denied permission, correction or repeated poke is not proof of cruelty. Raw poke timing does not measure physical force.

## Mood graph and slime acting direction

The [graph JSON](../boop-mood-spectrum-v2/mood-graph.json) and [mood handover](../boop-mood-spectrum-v2/HANDOVER.md) are authoritative for the proposed expanded system: 13 moods, 98 directed edges, implicit hold, and ordinary connectivity between all moods. Seven art moods were retained; six were added; none were deleted.

| Mood | Inventory | Suggested slime interpretation |
| --- | --- | --- |
| calm | Added | Low, settled dome; open relaxed eyes; small breathing movement. |
| happy | Retained | Big bright eyes and restrained smile; gentle buoyancy, occasional outside sparkle or music symbol. |
| excited | Retained | Clearly XD-like expression with open delighted mouth; taller rebounds and elastic overshoot. |
| proud | Retained | Asymmetric smirk; raises its front and presents a result with a theatrical hold. |
| curious | Retained | Alternating eye sizes, forward lean, peering around a prop; the body follows the gaze. |
| engaged | Added | Attentive eyes, efficient small leans and productive rhythm; little wasted motion. |
| determined | Retained | Slight upward brows, planted base and deliberate sustained effort; not angry brows. |
| annoyed | Added | Side-eye, compressed mouth, one pointed little correction. |
| irritated | Added | Eye twitch, short tense ripples and clipped repeated corrections. |
| grumpy | Retained | Compressed windup, sharp impacts, visible protest and destructive prop comedy. |
| whiny | Added | Pout and watery eyes; active pleading while continuing the task. |
| wounded | Added | Protective inward fold, fragile glance back and hesitant movement. |
| sad | Retained | Deflated posture, slower effort and plentiful tears; still recognizably the same body. |

The host Mood action prepares `hold` plus allowed neighbors for **JEV** to choose from. Ordinary edges are paced; dramatic edges require fresh qualifying evidence. JEV returns one offered choice, and code rejects stale or unoffered choices. The generic harness must not acquire graph policy. Pacing values in the graph handover are tuning suggestions, not approved production constants.

For example, grumpy → irritated → annoyed → engaged → calm is a recovery route; grumpy → whiny → sad is another. A justified dramatic grumpy → sad edge need not visit every intermediate mood. These are semantic decisions. Smoothly blending facial/body parameters after a decision does **not** create a new numeric mood-intensity API or invent intermediate persistent moods.

Changing terminal → searching preserves the current mood. The renderer may mute its outward expression during sleep without resetting stored mood. Current shipping `MoodAction` still offers six moods and initializes to happy; curious and the six added moods are not all wired into production. Do not assume loading the graph file enables them.

## Activity states and truthful selection

The review package has these 22 states. They are design meanings, not the current firmware's enum.

| States | Meaning and proposed slime performance |
| --- | --- |
| `no_app`, `asleep`, `idle` | Disconnected, sleeping, or awake without active work. Quiet shared resting motion where appropriate. |
| `listening` | Listening posture while the host is actually listening. Face turns toward the user; do not infer it from a delayed reply. |
| `starting` | New task, session greeting or continuation. Present a truthful NEW TASK, READY or CONTINUE card. |
| `planning` | Reliable planning context. Arrange steps using small body lobes or props. |
| `working` | Ongoing work without a more specific visual. Keep a workstation and body present continuously. |
| `terminal` | Bash or CLI activity. Typing, toy code and restrained binary effects; no raw commands or secrets. |
| `tool_use` | Generic fallback only when no specific supported tool family fits. |
| `searching`, `analyzing` | Outbound lookup versus inspection of returned material, when distinguishable from evidence. |
| `testing` | Reliable tests topic. Show running checks; do not invent passing tests. |
| `delegating`, `helper_return` | Actual helper dispatch versus return. Tiny helpers or comic squad reporting; no fabricated spawn from an end-only hook. |
| `waiting` | Waiting on the machine, not waiting for human approval. Quiet suspended work. |
| `needs_you` | Pending permission or question. Mood-shaped knocks followed by the recognizable alert ding and a prominent notification. |
| `reply_ready` | An answer is available without verified task success. Offer a card without a success trophy. |
| `task_complete` | Terminal result, explicitly success or failure. Victory versus struggle/warning, regardless of mood. |
| `error` | A tool or intermediate operation failed; the task may continue. |
| `stopped` | Interrupted or stopped, not failed and not completed successfully. |
| `poked`, `tap_spam` | Single interaction versus rapid repeated interaction. Add bounded physical impulses; never treat a tap as approval. |

Specific tool families win over `tool_use`. Use session/tool/event identity to deduplicate notifications. The current raw event specification has **eight** generic types, including `talk`; use [EVENTS.md](../../../plan/harness/EVENTS.md), not the older seven-type conversational example. A raw event type is not automatically a render state. Heartbeats and Boop's own actions must not recursively generate new announcements.

The selector needs two factual fields outside the mood/state pair:

- `hostContext.startContext`: `new_task`, `session`, `continuation`. Omission currently means session, not a new task.
- `hostContext.completionOutcome`: `success`, `failure`. Omission for task_complete falls back to reply_ready; an invalid nonempty value throws. A tool ending or a turn returning text alone is not proof of task success.

Pending attention remains rule-owned. Neither JEV, a gesture nor the renderer can approve, deny or clear it. Alerts must remain visibly truthful during transitions; respect the production core's existing grace, deduplication and clearing rules.

## Where the current code lives

Paths in this section are relative to the repository root. See the [animation package README](../boop-sound-bank-v4/README.md) for its full API and checks.

| Path | What to read or change |
| --- | --- |
| `internal/boop-design/boop-sound-bank-v4/runtime/catalog.mjs` | Combined asset inventory. `legacy-catalog.mjs`, `state-catalog.mjs` and `mood-catalog.mjs` supply entries. |
| `runtime/mood-art.mjs` inside that bank | New-mood choreography. One authored plan drives SVG stages and sound contacts. |
| `runtime/state-art.mjs`, `runtime/visual/` | Earlier state and pixel-character generators. |
| `runtime/bank.mjs` | `makeScene`, factual variation selection, event selection and sound synthesis helpers. |
| `runtime/player.mjs` | Browser reference player, clock, audio scheduling, cancellation and speech ducking. This is where whole-SVG replacement currently occurs. |
| `runtime/quiet-mix.mjs`, `runtime/audio/` | Routine sound thinning and procedural material/alert recipes. |
| `source/build.mjs`, `source/review.html` | Editable build and review sources. Do not hand-edit generated bundles. |
| `dist/boop-runtime.js`, `review/boop-moods.html` | Generated portable player and review page. |
| `manifest.json`, `coverage.json` | Manifest is generated and ignored; coverage is tracked. Build first on a fresh clone. |
| `internal/boop-design/assets/boop-voice-v1/` | Recorded speech/mumbles, dictionary, manifests, indexes and host-side reference selector. |
| `app/BoopKit/Actions/`, `plan/steering/` | Production actions and personality/mood policy, separate from the art bank. |
| `internal/tools/facegen/`, `internal/tools/sfxgen/` | Existing production asset compilers. These do not import the entire V4 review bank automatically. |

The current V4 inventory has **770 selections**: 308 preserved selections across seven moods and 462 additions across six moods. Each new mood has 77 selections: normally three per state, five for working, nine starting selections across three contexts, and six task_complete selections across success/failure. Some older mood/state cells still have only one action. Do not claim every old cell already has three variants. Sleep/disconnected choreography is intentionally shared.

## Existing animation and sound contract

This is the **implemented review API**, not a proposed glTF API. `makeScene(id)` returns `{asset, svg, score}`. This asset example was read from the runtime:

```json
{
  "id": "engaged.working.01",
  "mood": "engaged",
  "state": "working",
  "variation": 1,
  "action": "split-keys",
  "name": "Two-track flow",
  "caption": "Alternate between two compact keyboards and bring the results together.",
  "seconds": 5.076,
  "renderer": "mood-v4",
  "approval": "Review candidate",
  "sharedQuiet": false
}
```

Some entries additionally carry `startContext` or `outcome`. IDs are pack-local identifiers; resolve them through the catalog rather than guessing filenames. `renderer` currently selects hard-coded implementations. A new `characterId` or GLB path is not already recognized by the player.

The SVG uses a 320 × 240 viewBox. New-mood code shares an event plan between facial/body/action stages and cue timings. Existing artwork is deliberately stepped pixel art. It reserves the bottom 48 pixels for host text and has no decorative outer frame. Preserve that readable text region in the prototype's logical layout; a new hardware aspect ratio needs an explicit layout decision. New-style text bubbles should match the slime, not cover the face or alert meaning.

The score contains `id`, `seconds`, `policy`, `intervalSeconds`, `character`, `description`, `events`, `tailSeconds` and `mix`. One actual event is:

```json
{
  "at": 0.91368,
  "effect": "keyB",
  "gain": 0.175479,
  "pitch": 1.02,
  "label": "split-keys · contact 4",
  "sync": {"part": "mood-action", "step": 4, "pose": "stage-2"}
}
```

Times are local **seconds**, not event-log milliseconds. `effect` selects a synthesizer recipe, `gain` is an amplitude scale, and `pitch` is a frequency multiplier. `policy` distinguishes silent, entry-only, loop or sparse playback. Returning a visual to its first frame must not replay an entry-only ding every loop. Generated new-mood manifest entries also include suggested `voiceWindow` metadata; it is not returned directly by makeScene and does not guarantee arbitrary speech will fit.

Once the generated browser bundle is loaded, this is the current calling pattern. Start audio from a user gesture:

```js
const player = Boop.createBoopPlayer({
  mount: document.querySelector('#boop'),
  volume: 0.4
});
await player.setState({mood: 'whiny', state: 'terminal'});
await player.setState(
  {mood: 'wounded', state: 'task_complete'},
  {hostContext: {completionOutcome: 'failure'}}
);
player.setSpeechActive(true);
```

The reference `setState` deduplicates an unchanged pair and factual context, avoids the immediately previous variation where possible, and loops sustained states. Its sustained list is working, idle, asleep, no_app, planning, terminal, tool_use, searching, analyzing, testing and waiting. Other states currently play once through this API. That is a reference-player behavior, not a claim about every production visual.

## Sound and voice integration

Procedural SFX and recorded voice are separate layers. Existing SFX are code recipes using oscillators, noise and envelopes; the player synthesizes/caches short buffers on demand. They are not recordings embedded in an SVG. The shared plan keeps audible contacts aligned with visible contacts.

Keep the accepted quiet direction. Routine working sounds should be sparse clusters separated by silence, not constant uniform typing. Current quiet-mix code varies which authored clusters survive without jittering their timestamps away from the animation. Idle, asleep, no_app, listening and waiting scores are silent. Preserve the recognizable attention identity for needs_you, task_complete and error. No continuing music bed underneath speech.

For slime, a soft landing or squish can replace an appropriate material accent, but not every wobble needs a sound. Retain knock-then-ding notification semantics. Grumpy knocks can be stronger and faster; sad knocks lighter and slower. All use the same recognizable notification family. A failure cue must remain different from victory.

The [voice bank guide](../assets/boop-voice-v1/README.md) documents 2,752 actual takes in three available processing profiles, with some takes available only in robot-soft. These are **audition assets, not blanket listening approval**. Read `manifest.json`, `index.json`, `dictionary.json` and `select.mjs`; recording paths come from `recordings[].files`, not the archived master hash. The shipped files are unsigned 8-bit mono PCM WAV at 11,025 Hz. Recorded model provenance is in the manifest; do not regenerate based on older conversational model names.

The reference selector filters by state, mood, required facts, topic, review status, duration and recent use, then offers silence plus a small eligible shortlist. It runs on the host with filesystem access, not directly in the browser or ESP32. `--audition` is for review, not a way to bypass production approval. Default to one whole mini-utterance; use two-unit assembly only for compatible joins. Avoid arbitrary word-by-word stitching or silent cross-mood substitution. A new slime voice can reuse semantic intents without inheriting the Robot Minion timbre.

Proposed continuous player integration: share one playback timeline; reserve a voice slot after the ding or between contacts; duck routine SFX during voice, not the signature alert. Schedule audio against actual gesture markers after any retiming. Cancel stale queued clips on interruption. Maintain a host playback ledger and cooldowns: avoiding the previous ID does not guarantee a month without repetition. Voice volume/mute and reduced-motion controls remain independent.

## Why looping SVGs is not enough

The current player calls `stop()`, assigns `mount.innerHTML = scene.svg`, then starts the new scene at time zero. Matching first/last frames makes an individual clip loop cleanly, but does not make two different clips share body pose, velocity, props or camera. Crossfading entire pictures would produce two translucent blobs, not one physically continuous creature.

The new version therefore needs **a persistent scene and a motion controller**, not generated in-between images. It should keep the body, rig, camera, lights, floor and owned props loaded, and change their animation targets. This is an architectural addition, not a renderer flag already supported by the SVG bank.

## Recommended 3D implementation

**Recommendation for the first desktop prototype:** Three.js with one low-complexity slime mesh, a few authored deformation controls, procedural secondary wobble and a persistent scene. This fits the existing JavaScript review workflow. Blender can be used to author the mesh and clips; validate exports in the actual runtime instead of assuming the Blender viewport is the product.

Three.js provides a mixer attached to an object, weighted actions, crossfades, looping and time synchronization. These are building blocks for continuous motion, not automatic contact or prop continuity. [AnimationMixer documentation](https://threejs.org/docs/pages/AnimationMixer.html), [AnimationAction documentation](https://threejs.org/docs/pages/AnimationAction.html).

Use glTF/GLB for a shared rig and clips if needed. Core glTF supports node transforms and morph-target weights; morph targets deform the same mesh through weighted vertex offsets. It is not a portable container for an arbitrary live soft-body solver. Keep contact events and procedural dynamics in the character/controller data, and verify any material-animation extensions before relying on them. [Khronos glTF specification](https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html), [Three.js GLTFLoader](https://threejs.org/docs/pages/GLTFLoader.html).

For the jelly look, test a lit blue material with moderate roughness, restrained clearcoat and optional transmission/thickness. Three.js exposes these controls, but its physical material has a higher per-pixel cost as features are enabled. Our proposed first pass should sell softness with motion and highlights before adding expensive transparency. It need not be physically accurate subsurface jelly. [MeshPhysicalMaterial documentation](https://threejs.org/docs/pages/MeshPhysicalMaterial.html).

If the colleague prefers an editor-driven game engine, Godot's AnimationTree offers layered filtering, one-shots and immediate, synchronized or end-of-clip transitions. It is a viable alternative, not an additional dependency to add alongside Three.js. Its animation graph must remain separate from Boop's semantic mood graph. [Godot AnimationTree documentation](https://docs.godotengine.org/en/stable/tutorials/animation/animation_tree.html).

The following controller design is a project recommendation, not a claim that these libraries implement Boop's behavior automatically.

### Keep one deformable body

Use the same mesh topology and facial attachment system for every mood. Initial controls can include squash/stretch, left/right lean, front/back lean, local poke indentation, broad wobble and facial expression. A small rig can control large gestures; morph targets can control silhouette and face. Keep the ground-contact region stable and compensate horizontal bulging when vertically compressed so the creature does not appear to lose all volume.

Eyes and mouth must follow the deformed surface through shared skinning, deformation or a surface-aware attachment. Independent flat facial stickers at fixed world coordinates will slide or float. Update surface normals appropriately so highlights move with the deformation. Let the blob form simple rounded lobes when handling props; do not invent elaborate human hands unless separately approved.

### Preserve motion through interruptions

Model secondary jelly motion as a handful of damped springs or deformation modes, not a full fluid simulation. Conceptually, each mode has displacement x and velocity v; acceleration is `k * (target - x) - c * v`. A poke adds a bounded impulse to v. Keep x and v when a mood or gesture changes. This produces continuing oscillation instead of restarting the same bounce.

Use stable integration with bounded fixed substeps or an analytic spring update. Clamp input energy and deformation, especially during tap spam; do not feed unrestricted wall-clock gaps into an explicit solver after a suspended tab. Tune mass-like lag and settling visually. This equation is a design explanation, not a validated solver or final tuning preset.

If hardware exposes motion sensing later, filtered device acceleration could drive these impulses. The present event schema has no general shake vector; do not invent an IMU feed. Start the review with deterministic poke/shake controls. Physical sensing and its protocol are a separate capability decision.

### Separate layers and property ownership

| Layer | Proposed ownership |
| --- | --- |
| Persistent scene | Body identity, root position, floor, camera, material and existing props. Never reload on a routine state change. |
| Activity | Ongoing workstation action such as typing or searching. Keeps phase and prop ownership. |
| Mood | Face, resting posture and bounded timing targets. New mood blends from the currently displayed pose. |
| Gesture | A specific flourish, impact, recoil or card presentation with enter, action and recovery phases. |
| Secondary motion | Residual jelly wobble, blink/gaze variation and bounded contact impulses. |
| Attention and text | Rule-owned alert visibility and readable factual text. Never hidden merely to finish a flourish. |

Give each transform or morph channel one owner, or an explicit blend rule. Normalize overlapping clip weights. Do not let mood and activity both write the body scale independently each frame. Build additive clips against a declared reference pose; otherwise prefer explicitly blended controls. For an interruption, blend from the current evaluated pose and preserve procedural velocity, rather than snapping to either clip's authored first frame.

### Make activities continuous and props stateful

For a ten-minute working session, retain one keyboard and the same body. A local seeded scheduler can alternate short typing bursts, pauses, looks and approved gestures within the existing mood/state. It does not invent new moods, task outcomes or fresh tool calls. Select randomness at gesture boundaries, not fresh noise every frame.

Author enter, sustained loop, exit and recovery behavior. Routine changes can wait for the next short safe contact boundary; cap that wait. Attention must become visible promptly under the core's priority policy, even if a pose takes longer to settle. Synchronize compatible loop phases before crossfading; crossfade alone does not prevent sliding or mismatched key strikes. For incompatible actions, use a brief authored bridge from the current pose.

Track prop state explicitly: present, held, broken, offstage or recovering. If grumpy snaps a keyboard, its two halves must not instantly become an intact keyboard on the next loop. Give that gag an authored repair/replacement action or choose a next gesture compatible with the broken prop. Distinct actions should include flinging keycaps, snapping the keyboard and throwing it away, not three versions of the same particle effect.

An illustrative sequence: engaged terminal typing → irritated terminal typing keeps the keyboard and phase while the face tightens; a poke adds wobble without canceling work; needs_you becomes visible and typing yields while the body settles; when the host clears the request, work resumes from a coherent pose. If a terminal failure arrives instead, show failure without passing through a victory scene.

### Drive sound from motion markers

When a gesture is scheduled, derive its visible contacts and sound times from the same plan. Suggested semantic markers include key contact, prop impact, screen knock, alert reveal and landing; these are new controller concepts, not existing protocol fields. On transition, cancel markers belonging to the outgoing gesture token. Do not fire every crossed marker in a burst after resume. One new attention event may play its ding once; repeating the pending pose must not retrigger it.

## Proposed character adapter contract

This is a **design contract to implement and test**, not an existing plug-in API or device packet. Preserve the existing factual selector semantics while adding a renderer adapter around them. Do not put a GLB into the current `svg` string or assume new JSON fields are accepted by firmware.

| Proposed contract area | Required content |
| --- | --- |
| Pack identity | Schema version, distinct character ID, license/provenance, renderer kind, asset paths and supported mood/state coverage. Keep semantic variation IDs pack-local; namespace caches and storage by character ID. |
| Shared rig | One body identity/topology, named channels, reference pose, material, camera, face attachment, prop anchors and text-safe region. |
| Performance entry | Existing mood/state/variation meaning, action identity, factual start/outcome guards, duration or loop policy, and approval status. |
| Continuity metadata | Entry requirements, loop phase, safe exit markers, interruption policy, recovery action and expected prop states. |
| Cue plan | Contact markers, SFX recipe references, protected alert rules and voice-safe windows tied to the evaluated timeline. |
| Controller operations | Load once, accept validated semantic intent, add bounded interaction impulse, advance time, pause/resume, cancel obsolete work, expose diagnostics and dispose resources. |
| Fallback behavior | Unsupported combinations must be visible in coverage QA; use an explicitly documented compatible fallback without changing task truth. Never turn failure into success or silently change mood. |

The host resolves activity and priority, the Mood action validates graph traversal, and Voice owns speech selection. A character adapter only presents validated intent. Dependency injection or a renderer registry will be new work: the present player statically imports the SVG bank. Keep that bank operational behind its existing path while prototyping the new adapter.

## Device and storage boundary

The currently shipping device snapshot has asleep/idle/working bases, six moods and a separate attention field; moments and reactions add other visuals. It is not the 22-state review schema. See [StateSnapshot.swift](../../../app/BoopKit/Core/StateSnapshot.swift) and [PROTOCOL.md](../../../plan/PROTOCOL.md).

Current facegen compiles a restricted SVG design into integer drawing data; it is not a general SVG browser, WebGL renderer or glTF loader. See the [production face design guide](../../tools/facegen/design/README.md) and [DEVICE.md](../../../plan/DEVICE.md). Likewise, the recorded voice bank still needs suitable file playback/streaming integration on the existing ESP32 path.

The Space mentions a Waveshare prototype, but an exact board SKU, processor, display and transport have not been established here. Do not promise the 3D prototype runs on that board or the current ESP32. First demonstrate it locally on the paired computer. Then choose explicitly between a GPU-capable display host, a separate raster transport design, or an approved lighter 2.5D/baked fallback. Host rendering does not automatically provide a fast device video link. Baked frames also change storage costs and do not give arbitrary continuous deformation for free.

A mesh, textures and clips are assets even when playback is code-driven. Do not reuse the old compact SVG/SFX package size as a 3D budget estimate. Measure the chosen pack and runtime memory separately.

## Prototype sequence and acceptance

1. **Appearance approval:** one neutral blue slime, original face, stable floor contact and soft shading. Review full-body readability at native logical resolution before producing the full matrix.
2. **Continuity proof:** one persistent rig with idle, sustained working, poke and repeated poke. Demonstrate residual wobble across an interruption and a ten-minute working run without disappearance, reset flashes or growing resources.
3. **Emotion proof:** engaged → irritated → grumpy and whiny → sad on the same working body, plus happy versus excited. These are controlled preview sequences, not autonomous production mood policy.
4. **Priority and truth proof:** needs_you interrupt; request stays pending through pokes; clear resumes work; separate success, failure, error and reply_ready; outcome never follows mood.
5. **Sound proof:** sparse motion-aligned material accents, recognizable knock/ding, distinct success/failure cues, one voice slot with ducking, no extra musical bed. Review with and without voice.
6. **Expand after approval:** all 13 moods and 22 design states, normally three substantially different performances and five for working, with starting/outcome contexts and shared silent cells explicitly covered. Use a generated coverage report, not guessed counts.

Proposed QA should inspect pose and velocity continuity, face attachment, floor penetration, extreme combined morphs, prop recovery, sound contact offsets, duplicate/stale events, interruption at every gesture phase, long tab suspension, reduced motion, mute and offline operation. Seeded replay must reproduce the same gestures. Measure p95 event-to-visible latency, frame time, memory and battery impact on the target Mac/PC. A stable 30 fps prototype is an initial target to validate, not a benchmark already achieved. Avoid rapid full-screen flashing; exaggerated acting need not mean strobing.

Existing source checks, from the repository root:

```sh
node internal/boop-design/boop-mood-spectrum-v2/validate.mjs
node internal/boop-design/boop-sound-bank-v4/source/build.mjs
node internal/boop-design/boop-sound-bank-v4/qa/check.mjs
```

The [package guide](../README.md) explains optional browser QA, offline review and SVG export. A colleague should use their own checkout and portable review, not the author's localhost URL. New 3D tests will be additional; passing the SVG tests does not validate a slime rig.

## Handover prompt for the colleague

```text
Create a separate jelly slime character prototype for Buddygotchi. Read this handover, repository AGENTS.md, internal/boop-design/README.md, the V2 mood graph handover, the V4 animation bank and the voice-bank guide before implementation. Confirm the latest code baseline and preserve unrelated work.

Use the supplied light-blue slime sheet for broad silhouette and color inspiration and 96594.MP4 for tactile jelly-motion reference. Make an original face and identity, not a copy of Rimuru or Ditto. Keep Boop's overconfident, dramatic, emotionally transparent, easily wounded, secretly needy character. This is a full-body 3D-like blob with soft volume and readable expressions, not a replacement set of flat emojis.

Build one persistent scene and body. Prefer a small Three.js mesh/rig with morph controls, authored gestures and bounded procedural spring wobble for the first desktop review. Preserve pose, velocity, camera, face attachment and prop state across changes. A second poke must add to existing wobble. Do not generate frames with an LLM or diffusion model and do not swap complete bodies at every state change. Use one motion/cue timeline for sparse procedural SFX and optional recorded voice.

Reuse the 13-mood graph and 22-state design semantics. JEV chooses offered semantic options; code validates them. Changing activity must not reset mood. Task outcome and pending attention remain host facts. Boop never approves, denies or clears agent permissions. Do not infer actual shake sensors, emotion intensity or new protocol fields from this brief.

The current SVG API is not a 3D plug-in system. Propose the renderer adapter and shared-rig/performance metadata explicitly, preserve the old renderer, and keep prototype work internal. Start with appearance and continuity proofs, then working with a few contrasting moods, attention, poke, success and failure. Show the owner a review before filling the complete variation matrix. Deliver editable sources, reproducible builds, coverage, provenance and measured performance/continuity tests, clearly distinguishing implemented behavior from proposals.

Ask for the exact display/board and transport before promising device delivery. Do not push, open a PR, merge, deploy, change firmware or enclosure interfaces, spend generation credits, or replace accepted assets without explicit consent. Reading this prompt does not itself authorize those actions.
```
