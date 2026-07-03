# Media assets

Drop final photography/video here using the **exact filenames** below. Until a
file exists, the `Media` component renders an art-directed placeholder and swaps
in the real asset automatically when present (no code change). See `SPEC.md §8`.

| File | Section | Spec |
| --- | --- | --- |
| `hero-loop.mp4` (+ `hero-poster.jpg`) | S1 | ~12s loop, ≤ 4 MB, H.264 1920×1080, muted, no audio track, desk-eye level |
| `moment-asks.jpg`, `moment-pet.jpg`, `moment-work.jpg` | S2 | 4:3 stills, ≤ 300 KB each |
| `alive-wobble.mp4`, `alive-sleep.mp4`, `alive-celebrate.mp4` (+ posters) | S3 | 3–5s loops, ≤ 1.5 MB each, 4:5, lazy-loaded |
| `exploded.jpg` | S6 | 4:5 render, ≤ 400 KB (the one acceptable render) |
| `box.jpg` | S7 | 4:3 still, ≤ 300 KB |

Photography direction: real desk, morning side-light, wood + one plant, shallow
depth of field, slight grain; blob at eye level or slightly below — never from
above (shrinks the face); hands in ⅔ of shots; one night scene with amber as the
only warm source.

Also replace `../og.svg` with a real `og.jpg` (1200×630) and update the reference
in `src/app/layout.tsx` when it exists.
