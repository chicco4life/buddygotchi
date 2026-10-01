# Plan: Boop's whole voice on the SD card

Drafted 2026-09-29, revised the same day after the owner's review. Nothing
here is built yet; it waits for the owner's go.

## What we're after

Boop says nothing in about half the moments that matter most. When a turn
fails it often wears a sad or wounded face, and those faces have no take
to say, so it goes quiet instead of swearing or sighing. Being told off
gets the same silence. Federico's bank (2,722 takes on
`origin/codex/boop-mood-spectrum-v4`) fills those gaps, but at about
43 MB it can't live in the board's 4 MB of flash.

The board's own microSD slot works (checked 2026-09-29: a 64 GB card,
reformatted as FAT, reads at about 900 KB/s, and a take's first 4 KB
arrives within 19 ms). So every take moves to the card, the 40 we have
included, and they all play the same way.

The owner's two rules for the voice:

1. **Keep every take.** Two takes of the same word in the same mood just
   give Boop more to choose from.
2. **No blank cells.** For every face and every answer the brain can
   give, there's something to play.

## 1. Two questions: how Boop feels, and what it's about

Before the recorded voice, Boop mumbled a line with up to two real
words: an exclamation for the feeling (`word.feeling`) and a topic word
for what it was about (`word.about`, such as "tests").
That pattern comes back. Many of Federico's takes are topic words
(Launch, Rerun, Cleared, Test, Search, Compile), and they fit the
second question.

Jev answers:

- **`say.feeling`: how Boop feels about NOW.** `none`, `upset` (something
  went wrong, or a letdown), `glad` (something went right), `tickled` (a
  poke, kind words).
- **`say.about`: what NOW is about.** `none` or one of 15 topics, each of
  which the brain can already see in NOW (EVENTS.md): `start`, `helpers`
  (a subagent starting), `helper back`, `retry`, `work`, `tests`,
  `command`, `tool`, `looking` (searching or reading), `planning`,
  `done`, `answer`, `stopped`, `waiting`, `quiet`.
- **`say.kind`: how big the feeling's take is,** as today: sound, word,
  phrase or swear.

Voice then builds the line: the feeling's take, then the topic's, such
as "Ugh… Tests" or "Yay! Done". Either can be missing. This follows
Federico's rules for joining takes: at most two, 2.8 s at most, and a
phrase plays alone.

This replaces today's `say.meaning`, which has 11 options.

**Where every take goes** (full list: [picks.md](picks.md), made by
[select.py](select.py)):

| Answer | Federico's groups | Takes |
| --- | --- | --- |
| upset | frustration (the swears included), setback, deflate | 259 |
| glad | celebrate, delight, relief, pride, insight | 211 |
| tickled | poke | 107 |
| start | begin | 142 |
| helpers | delegate | 112 |
| helper back | return | 128 |
| retry | retry | 112 |
| work | work, effort | 177 |
| tests | test | 112 |
| command | terminal | 104 |
| tool | tool | 104 |
| looking | search, analyze, ponder | 258 |
| planning | plan | 112 |
| done | success | 127 |
| answer | reply | 112 |
| stopped | stop | 112 |
| waiting | wait | 138 |
| quiet | idle | 104 |
| needs you (the rules' only) | attention | 191 |

That's all 2,722 takes, about 65 minutes of audio. **No cell is empty:**
every feeling and every topic has takes in all 13 faces. Two limits
remain, both on purpose:

- **Glad in a bad mood** (annoyed, irritated, grumpy, whiny, wounded,
  sad) has only relief sounds ("Phew…"), which play only on a success.
  At other times a grumpy Boop being glad says just the topic word.
- **Swears** stay in upset, only in annoyed, irritated and grumpy
  (18 takes, where we have 3 today), and only on a failed turn. Sad and
  wounded have none, because none were recorded.

**Words that state a fact** only play when the brain's answers back them
up. For example, "Passed" needs `tests` and a success, "Fixed" a
success, and "Failed" or "Broken" an `upset` at a failure. The fact each
one needs is already in Federico's dictionary (`requires`).

**Picking a kind never leaves a cell silent.** Today, when nothing of
the asked-for kind fits, Voice steps down to a plainer kind and stops at
sound. The new rule tries the nearest kind in either direction, but
never steps up to a swear.

**Steering, to make Boop swear more.** A failed turn goes irritated,
upset, with a swear. Sad is kept for an agent giving up
(upset, a sigh). Rude words get wounded, upset ("Aww…"). Pokes get
tickled.

## 2. Listening

None of the 2,722 has been heard, and the owner chose to ship them as
sorted (§4). If a take sounds wrong later, Federico's audition page
(`python3 -m http.server 4177 --directory internal/boop-design/assets/boop-voice-v1`,
then `/review/`) exports Keep and Rework marks as JSON, and voicegen
drops anything marked Rework.

## 3. The work, in phases

Each phase is checked on the real board before the next starts
(VERIFICATION.md §1), and each updates its specs in the same commit.

**Phase 1: the takes in the repo, and voicegen**
- Bring over the robot-soft WAVs only (about 43 MB, in plain git) and
  the bank's manifest and dictionary, not Federico's branch, whose
  history is about 713 MB with three copies of every take.
- Check in `select.py`'s sorting as voicegen's input, plus the review
  export once it exists.
- voicegen writes a folder for the card (one file per take: a small
  header with its text, length and mouth, then its samples) and
  `Takes.swift` with every take and its answer. It stops writing
  `voice.h`.
- Specs: VOICE.md §3, VERIFICATION.md.

**Phase 2: the Mac, the two questions and the steering**
- Replace `say.meaning` with `say.feeling` and `say.about` in
  `ReactAction` (DECISIONS.md §3, §5). Voice builds a line of up to two
  takes, with the kind rule above.
- The protocol's `say` carries up to two takes (PROTOCOL.md §3).
- Steering as in §1: boop.md, chatter.md, and the app's copy.
- Evals: a failed turn swears; being told off sighs; a poke answers; a
  failing check says "tests". Rerun the scenarios that touch reactions
  once each (keeping Jev calls few).
- Specs: DECISIONS.md, VOICE.md §2, §4 and §6, EVALS.md.

**Phase 3: the board plays from the card**
- Mount the card at boot. Touch moves to software SPI so the card can
  have the second hardware bus.
- The player streams a take from its file through a small buffer and
  plays a two-take line with a short gap between them. It loads each
  header (text, length, mouth) as soon as a line arrives, so the mouth
  and bubble stay in time.
- `dbg.ping` and the link's hello report whether a card is in and a
  fingerprint of its voice folder. The Mac only asks for takes when that
  fingerprint matches its own `Takes.swift`; otherwise Boop is silent,
  and faces and sound effects carry on.
- Delete `voice.h` from flash, which frees about 450 KB. Sound effects
  stay in flash, because they're timed to the animations.
- The simulator and the native tests read the same folder from disk.
- Measure free RAM with the card mounted. The target is at least 50 KB;
  it's 72 KB today.
- Specs: DEVICE.md (the slot, the pin map, the RAM budget), VOICE.md §8,
  PROTOCOL.md §3 and §5, and a line in ARCHITECTURE.md's decision log
  saying why Boop now depends on a card.

**Phase 4: filling the card, and the board check**
- `voicegen --card /Volumes/<card>` copies the folder onto the card,
  which you'd plug into the Mac.
- `boopctl takes` plays every take from the card and checks each one's
  length. Then the soak (L2) and the pipeline check (L4) over USB.
- A failed turn, being told off, a poke and a failing check, on the
  board, with the words logged. Evidence goes in this folder.

## 4. The owner's answers (2026-09-29)

1. **Two questions**, a feeling and a topic, in place of `say.meaning`: yes.
2. **A failed turn goes irritated** (upset, with a swear), not grumpy.
   Sad is kept for an agent giving up.
3. **The audio lives in plain git.**
4. **No listening pass first.** The picks go in as sorted; the board check
   in Phase 4 is where they're first heard.
5. **No card means no voice.** No fallback in flash.
6. **Sad and wounded swears:** Federico gets a request to record them
   ([FEDERICO.md](FEDERICO.md)); they drop into the bank when they land.
