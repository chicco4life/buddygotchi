# Media assets

The page has exactly **two** media slots (SPEC.md Amendments A/B) — both
intended for generated mock images until real photography exists. Drop files
here using the **exact filenames** below; the `Media` component shows an
art-directed placeholder until the file exists, then swaps it in automatically
(no code change).

| File | Section | Spec |
| --- | --- | --- |
| `hero.jpg` | S1 (full-bleed hero) | ~2400×1600, ≤ 500 KB. Blob on a real wooden desk, warm morning side-light, amber glow, a hand mid-pet, shot at desk-eye level (never from above). |
| `box.jpg` | S6 (the adoption) | 4:3, ≤ 300 KB. Open adoption box: blob nested in the insert, numbered tag visible, braided cream cable coiled. No care card (dropped per Amendment B). |

Everything else on the page is drawn (`BuddyBlob`, the light strip, the drawn
adoption box) and needs no assets.

Generation direction for the mocks: warm practical light, real wood desk, shallow
depth of field, slight grain; the blob is a squashed cream sphere, wider than
tall, with a small dark screen-face slightly above its midline and two blush
dots; hands in frame create ownership. One night-variant of the hero (amber as
the only warm source) is useful for ads and the OG image.

When the real product exists: reshoot both slots as photography, add the S3
loops and hero film back (the video-capable `Media` component is in git history,
pre-Amendment-A), and replace `../og.svg` with a real `og.jpg` (1200×630),
updating the reference in `src/app/layout.tsx`.
