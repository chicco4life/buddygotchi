# Boop base mood–state SVG review

Revision 1 · 2026-09-27 · Awaiting design approval

This pass contains **one base design for each of the 42 mood–state pairings**. It does not create the additional variations in the expression catalog.

## Contents

- `svg/`: 42 standalone animated SVGs, named `mood--state.svg`.
- `manifest.json`: complete mood/state-to-file mapping and approval status.
- `source/design-system.mjs`: reusable drawing source, exporting `renderSVG(mood, state)`.

There are **30 distinct visual designs**. The four expressive states have a separate design for each of the seven moods. Asleep and no-app deliberately ignore mood and each reuse a single design across seven filenames.

## Visual language

- Native 320×240 coordinate system with a black field, warm-white four-block eyes, a tiny mouth, and paired coral cheek blocks.
- Pixel-stepped eyelids distinguish the moods. No smoothing, gradients, blur, or continuous rotations.
- Happy has gently smiling eyes; excited has taller, brighter eyes; proud has uneven half-lids and a smirk; curious has asymmetric eyes; determined has restrained inward lids; grumpy has a deeper scowl; sad has raised inner corners, a quivering mouth, and blue tears.
- Active props occupy the space below the face. The bottom 32 logical pixels remain available for the application's status area.
- Working uses a keyboard with mood-specific rhythms. Grumpy has one compact keycap bounce; sad keeps typing through small tears.
- Needs-you uses one amber request symbol. Task-complete uses a neutral result card and tray, not a success checkmark.
- Requests slightly open the eyes toward the user. Completion softens the determined face and lets a small smile escape the grumpy face; sad completion retains tears with a relieved smile.
- All previews are silent.
- Asleep has closed eyes and a slow breath. No-app has a persistent broken-link cue and relaxed low eyes.

## Animation and editing

The files contain native SVG geometry and SMIL animation. They require no external images, fonts, scripts, services, or API keys. Open a file in a browser to preview it, or import it into an SVG-aware editor to edit the shapes.

Translations use discrete integer steps. Blinks, breath, typing, and occasional mood gestures loop. Request and result entry gestures play once and settle. A browser preview can call `pauseAnimations()`, `unpauseAnimations()`, and `setCurrentTime(0)` on the SVG element to pause or replay.

Each file contains an animated group and a static reduced-motion group. The system's reduced-motion preference selects the still pose by default. Explicit playback in the review surface can enable the animation for inspection.

The review supports switching among seven moods, pausing all seven state previews, and replaying one or all. One-shot entry gestures can be replayed while inspecting needs-you and task-complete.

## Scope

These are review candidates, not approved production assets or a device integration. The two external controls remain `mood` and `state`; file names and playback controls do not add agent parameters. No voice scripts, audio recordings, enclosure changes, or full variation bank are included.

After approval, these base shapes and cues can be used to build the remaining authored variations. Feedback should identify the mood and state, then distinguish changes to the face from changes to timing or props.
