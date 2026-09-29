# Request for Federico: sad and wounded swears

Paste the part below the line to Federico, or to the agent he records with.

---

Hi Federico! Boop is taking your whole voice bank: all 2,722 takes are
moving onto the board's SD card. Thank you, it fills almost every gap.
One gap is left, and it's the one we care about most: **swears in the
sad and wounded moods.**

**Why.** Today the swears (Shit, Fuck, Damn, Crap, Shiba) exist only in
annoyed, irritated and grumpy. We're steering a failed turn to
irritated so Boop swears, but when a long piece of work fails, or the
agent gives up, Boop wears a sad or wounded face and has no swear to
say. We'd like a deflated, under-the-breath swear for those moments.

**What to record**

- The same five swear entries you already have (`explicit.shit`,
  `explicit.fuck`, `explicit.damn`, `explicit.crap`, `explicit.shiba`).
- In three more moods:
  - **sad**: deflated, quiet, trailing off, like "…fuck." after a long
    sigh;
  - **wounded**: hurt and small, a wince rather than a curse;
  - **whiny**: sorry for itself, a little stretched.
- Both of the entries' variants (`contained` and `trailing`): that's
  5 swears × 3 moods × 2 variants = **30 takes**.
- Keep them the same rules as the existing swears: at a failure, never
  at the person, `requires: failure_confirmed`, `explicit: true`.

**How we'll use them.** Same setup as the rest of the bank, so they drop
in without changes on our side:

- Robot Minion 1 (`rErOatUrNIU3vfNcLl6Z`), `eleven_v4`.
- Processed like the others: the robot-soft texture, 8-bit PCM, mono,
  11.025 kHz (`tools/compress.py`).
- Added to `manifest.json`, `index.json` and the dictionary's `moods`
  list for those five entries, with `reviewStatus:
  unreviewed-by-ear`, and passing `tools/check.mjs`.
- Pushed to `codex/boop-mood-spectrum-v4` as its own commit. Only the
  robot-soft WAVs are needed; please skip the original and robot-grain
  copies for these, and don't include MP3 masters in git.

**If you have time for a second, smaller batch (optional):** grudging
good-news takes for the bad moods, which play whether or not a turn
succeeded. Right now a grumpy or sad Boop can only be "glad" with a
"Phew…" at a success. Something like "Fine.", "Finally.", "About time."
and "Hmph, okay." in annoyed, irritated, grumpy, whiny, wounded and sad
would round it out, maybe under a new entry such as `word.grudging`,
`intent: celebrate`, with no `requires`.

Thanks!
