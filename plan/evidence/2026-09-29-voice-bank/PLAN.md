# Recorded voice bank v1: integration plan

Updated 2026-09-29. How Federico's recorded voice bank on
`codex/boop-mood-spectrum-v4` (`5b2d7cc7`,
`internal/boop-design/assets/boop-voice-v1/`) could become Boop's voice
on the board. It's a work plan, not a spec. **Status:** built as option B
on 2026-09-29, with the decisions and results in [README.md](README.md). The package's own guide is its
[README](../../../internal/boop-design/assets/boop-voice-v1/README.md)
once it's merged.

## 0. What the package is, measured

Forty short recordings of one ElevenLabs voice ("Robot Minion 1"), each a
word, a sound or a short phrase performed in one mood: "Go", "Done",
"Again", "Hello", "Hrr…", "Tsk…", "Phew…", "Yatta", "Mamma mia". There
is no recorded gibberish. The package also has a 387-entry dictionary of
planned performances, lookup indexes and a reference selector in
JavaScript.

| Fact | Measured how |
| --- | --- |
| 40 takes: 20 older auditions (`previous.*`) and 20 new (`new.d01`–`d20`), 58.5 s in all | `manifest.json`, `storage-report.json` |
| Each take in three textures (robot-soft, the recommended one; original; robot-grain), 44.1 kHz 16-bit mono WAV, 5.2 MB a texture, plus 40 MP3 masters: 16.9 MB in all | the same |
| **Every take is `unreviewed-by-ear`.** The selector plays none without `--audition` until a take is marked `approved` | `select.mjs` |
| 34 takes are in one of the 13 moods: calm 1, happy 5, excited 2, proud 3, curious 3, engaged 3, determined 2, annoyed 5, irritated 1, grumpy 5, whiny 2, wounded 1, sad 1. Six are in moods we don't have (relieved, weary, amused, unspecified) and need a mood by ear | `manifest.json` |
| 3 swears (Shit, Fuck, and Korean Shiba), 4 phrases (Mamma mia, Bada bing bada boom, Tiny genius, Knock knock), borrowed words (Dai, Basta, Aigo, Yatta), 5 for needs you (Oi?, Hello ×3, Knock knock) | the dictionary's categories and required facts |
| Each take starts with about 0.2 s of near-silence and ends with about 0.35 s: trimmed at −45 dBFS with small pads, the 40 last 42 s | scratch measurement |
| At today's voice format (8-bit, 11.025 kHz) the trimmed 40 take **452 KB**; without the swears and "Mwahaha" (2.9 s, too long for routine use), 394 KB | scratch conversion |
| Robot-soft is low-passed at 4.2 kHz, so 11.025 kHz (a 5.5 kHz ceiling) keeps all of it. The only loss is 16-bit to 8-bit, and the board's DAC is 8-bit anyway | `provenance.json` |
| app0 has 632 KB free (2,498,591 of 3,145,728 bytes used), so all 40 fit with today's voice kept, leaving the firmware at 94% of app0 (92% without the swears and Mwahaha) | DEVICE.md §5, §6 |
| The commit merges onto main with two conflicts, both navigation lines in `internal/README.md` and `internal/boop-design/README.md` | `git merge-tree` |

**Coverage.** Of the 19 Examples in `personality/boop.md`, about 6 have a
take performed in the Example's face mood whose required fact fits:
happy finishes (Finish, Yay, Yatta, Phew), engaged work (Work, Rrr… tik),
annoyed at a failed check (Basta, Tsk, Pfft), and a turn starting,
determined or excited (Dai, Again, Go). Sad, curious, wounded and proud
reactions, determined at long work, pokes and words to Boop have none. A
failed turn's grumpy face has only the swears and the "Mamma mia"
phrase, and a very long turn's excited finish only "Bada bing bada boom".

## 1. Concepts, old to new

| Concept | Today | With recordings |
| --- | --- | --- |
| What Boop says | A gibberish line (2–8 synthesized syllables) with at most one real word, built by Voice from a feeling and a dialect | One whole recorded take, or silence. No syllables, tune or dialect |
| Who picks it | Jev picks a word from two lists (`word.feeling`, `word.about`); Voice builds the line in the face's feeling | Jev picks what Boop means (an intent: begin, success, frustration…); the Mac picks a recording of that meaning performed in the face's mood |
| The mood of the sound | `Voice.feeling(forMood:)` maps 13 moods to 8 feelings, some borrowed "until their recorded voice arrives" | The take's own mood must be the face's (the bank's rule: no silent substitution) |
| Facts a line must respect | None in code; Jev judges from NOW | The bank's "required facts" split in two: success-only and failure-only takes play only with that `react.animation` answer, checked in code; the rest ("a turn starting", "work going on") go in each option's meaning, for Jev to judge from NOW, as today's words do |
| On the wire | `say: {syl, word, at, tune, ms}` | `say: {take: "new.d02"}`; the board has each take's samples, text and length |
| On the board | 64 syllables and 42 words, 235 KB, resampled per beat | Plus the kept takes, about 0.4 MB, each played whole at its own pitch; the mouth follows its loudness, the bubble shows its text |
| When nothing fits | Every reaction mumbles | Silence, or today's mumble (decision D1) |
| Pacing | Steering and Jev | The same. The bank's per-hour caps and cooldowns stay out of code (your rule that pacing is the steering's); only "not the same take twice in a row", as finishes' variations already do |

## 2. Where it pushes against today's rules

- **VISION.md principle 2** and VOICE.md §1: "Minion mumble with at
  most one real word", and that word English. Recorded takes are the
  word with no mumble around it, some aren't English (Dai, Basta, Aigo,
  Yatta), and four are phrases.
- **VOICE.md §7** bans rude words in the gibberish. The bank has three
  swears, gated behind an explicit switch in its own selector.
- **Needs you:** no line plays while something needs you, so the ding
  is always heard (BEHAVIORS.md §3.2, and your call to drop the chirp).
  The bank's five needs-you takes ("Hello?", "Oi?", "Knock knock") only
  fit if the device plays one after the ding, as a rule.
- **Talked to, Boop always answers with a face.** The pilot has no take
  for words to Boop or pokes, so under D1 (a) those faces are silent.
- **One voice.** The handover asks for one recognisable voice across
  moods. Recorded takes next to today's synthesized mumble are two
  voices in one creature (D1 (b)).

## 3. Decisions

| # | Question | Options | Recommendation |
| --- | --- | --- | --- |
| D1 | When Jev's pick has no take in the face's mood | (a) silence, the bank's rule; (b) today's mumble with its word, until more takes are recorded | Decide after hearing the takes on the board (V2–V3). The runtime is the same either way; only the fallback differs |
| D2 | Swears (Shit, Fuck, Shiba) | Never flash them; or behind a setting | Never, for now: a desk creature, and VOICE.md §7's spirit |
| D3 | Phrases and borrowed words | Allow, rare; or English words and sounds only | Allow: they're the charm, and VISION's principle 2 gets rewritten either way |
| D4 | A voice for needs you | The ding stays the only alert; or the device adds one take after it | The ding stays, as you decided for the chirp |
| D5 | What to merge | Federico's commit as-is (16.4 MB of audio into main's history, already on origin); or only robot-soft and the metadata | As-is: his later pushes merge cleanly, and the objects are already on origin |
| D6 | Loudness on the board | "Driven" (saturated like today's syllables, about as loud) or "clean" (only levelled, about half as loud) | By ear, per the listening page |

## 4. Phases

Each phase ends green (build, Swift tests, firmware tests) and commits
with its spec updates, as CLAUDE.md's table says.

**V0. Base.** Branch from main; merge `5b2d7cc7`; resolve the two
README conflicts. Checks: the bank's `tools/check.mjs`, `make build`,
`make -C internal test`.

**V1. Listen.** You go through the listening page: keep or drop each
take, give the six alias takes a mood, and choose driven or clean. Your
picks become `reviewStatus: "approved"` in the bank's manifest (its
README says approvals live there and must survive a re-import).

**V2. Takes on the board.** No change to the brain.

- An asset tool (a `--takes` mode of voicegen, or `takegen`) reads the
  bank's manifest and writes `firmware/assets/takes.h` (samples, text,
  length) and a generated `app/BoopKit/Voice/Takes.swift` (id, intent,
  mood, required fact, category, length), as facegen writes `FaceLoops`.
  It ships approved takes, or every take with `--audition`: trimmed,
  8-bit, 11.025 kHz, levelled per D6. `dbg.ping` reports its version.
- The player plays a take whole at its own pitch: no tune, jitter or
  speed-up, and a cut fades as a line's does. The mouth opens while the
  take is loud, and the bubble shows its text.
- The protocol gains `say.take`. A take the board doesn't have plays
  nothing. `ended` is unchanged.
- The Mac's `DeviceMoment` can carry a take, and `sayMs` uses its length.
- `boopctl play --take ID` plays one on the board, and `boopctl takes`
  plays them all, as `boopctl mumble` does the feelings.
- Tests: the player's timeline for a take, the protocol parse, a size
  budget for takes.h, a simulator golden with a take's bubble. Specs:
  VOICE.md §8, PROTOCOL.md §3, DEVICE.md §5, VERIFICATION.md §2.

**V3. Listen on the board.** You hear them on the speaker (USB, with
`boopctl takes`) and settle D1. The approvals from V1 can change here.

**V4. The brain.**

- `word.feeling` becomes `say`: `none` plus the intents that have an
  approved take, each with a meaning and a "not for" written by hand.
  With the pilot fully approved, that's up to 11 intents (needs you's
  excluded per D4). The options grow as takes are approved.
- `react` picks a take: approved, with that intent, performed in the
  face's mood, its required fact agreeing with `react.animation`, and not
  the one it played last when another fits. With none, D1's fallback.
- HISTORY says what Boop said, `…and said "Done."`, so "don't repeat
  what Boop just did" keeps working.
- `word.about` stays only if D1 keeps today's mumble.
- Steering: boop.md's Examples and each mood file's "Words it likes"
  name intents. Evals: 16 of the 55 scenarios name words and change.
  Specs: VISION.md principle 2, VOICE.md (rewritten), harness/DECISIONS.md
  §3 and §5, BEHAVIORS.md, and a decision-log row in ARCHITECTURE.md. If
  D1 is (a), the gibberish generator, dialects, the unintelligibility
  check and voicegen's syllables are deleted, which frees their 235 KB.

**V5. Checks.** `make eval` (it needs Jev credit: the key hit HTTP 402
overnight), a headless day, the board over USB (L2, L4, a soak), and
your listen.

## 5. Risks

- **Coverage.** With D1 (a), most reactions today would be silent faces
  until more takes are recorded and approved (§0).
- **Flash.** After the pilot, the firmware is at 92–94% of app0. At this
  format the rest of app0 plus the unused 896 KB partition hold under two
  more minutes of takes (a little over two if the gibberish's 235 KB
  goes). The full dictionary (7,123 planned
  performances) needs the microSD slot, which is unused today
  (DEVICE.md §1).
- **Jev's list.** The full dictionary has 28 intents, too many for one
  question. They'd have to be filtered by what Boop is showing, a new
  pattern for the harness.
- **Sound on the speaker.** The previews play on the Mac. Speech at
  8-bit on the board's speaker is untested.
