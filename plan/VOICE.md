# Boop: voice

Updated 2026-09-26. How Boop's gibberish is built, how it sounds, and how we
keep it unintelligible. Numbers marked *proposed* are first guesses, to be
tuned by ear.

## 1. What we're after

Boop should sound like a Minion from the films: fast, bouncy and full of
feeling, with not a single word you can make out, except that now and then
one real English word pops out and lands, like *"…tests?"*.

Three qualities matter most:

- **Emotion first.** You can tell happy, annoyed, sleepy or curious with
  your eyes closed.
- **Unintelligible.** Nothing but the one real word sounds like English, or
  like any language you speak.
- **Recognisably this Boop.** Each Boop has its own favourite sounds, so two
  Boops side by side sound related but not identical.

We take the *feel* of Minion speech: open vowels, bouncy rhythm, a
pseudo-Romance lilt. We don't copy its actual words or catchphrases, which
belong to the films.

## 2. Who does what

| Step | Done by |
| --- | --- |
| Decide to say something: a feeling and maybe one word | The brain or a rule, by calling the `say` action |
| Build the line: syllables, where the word goes, tune and tempo | Voice, on the Mac |
| Check it isn't accidentally English | Voice |
| Send it to the device | `say`, through the device link |
| Play it | The device |

Voice is the only code that knows what Minion speech is. The brain never
writes syllables; it picks a feeling and at most one word from a fixed
list. That keeps the voice the same whichever brain is in use, and no model
can slip real words into the gibberish.

Voice is made once per Boop, with its dialect (§3), and has one function:

```
Voice(dialect)
  line(feeling, word?, seed) -> { groups, word, at, tune, ms }
```

`groups` are the gibberish words, each a list of syllables; `at` is where
the word goes, as an index into the syllables; `ms` is milliseconds per
syllable.

## 3. The syllables

**Sounds we use:** soft, rounded consonants and pure open vowels, which is
where the Minion bounce comes from.

- Consonants: `b p m n d t l k g y w`
- Vowels: `a e i o u`, always pronounced as in Italian
- Shapes: mostly consonant + vowel (`ba`, `mi`, `po`), sometimes ending in
  `n` or `m` (`pum`, `lon`), and sometimes a bare vowel (`a`, `o`) for gasps
  and trailing off

**Sounds we avoid:** `s`, `sh`, `f`, `th`, `r` and `v`. They make gibberish
sound like real speech and are hard to play cleanly on an 8-bit speaker.

**The full set** is 64 syllables, fixed in the firmware
(`app/BoopKit/Voice/Sounds.swift` is the source):

- the 45 pairs of `b p m n d t l k g` with `a e i o u`;
- the glides `ya yo yu wa we wo`;
- the bare vowels `a e i o u`;
- six closed syllables that aren't English words: `pum lon kun tem gom lun`;
- two hums, `mm` and `nn`, for sleepy lines and the safe hum.

**Each Boop's dialect.** At setup, Boop's random seed picks 16 favourite
syllables from the full set (not the hums). About 70% of syllables come
from the favourites that suit the feeling, and the rest from the whole set.
The dialect never changes, so your Boop always sounds like itself.

## 4. Building a line

A line is 2–8 syllables, grouped into gibberish "words" of 1–3 syllables:

```
 ma-po  li  bu-da…  tests?
 └─ gibberish ─────┘ └ real word
```

| Part | Rule |
| --- | --- |
| Length | Voice picks short (2–4 syllables) or long (5–8), from the feeling. Excited is usually long and sleepy almost always short |
| Grouping | Groups of 1–3 syllables. Doubling is common (`po-po`, `ba-ba`), because it sounds playful: 40% of two-syllable groups for happy and excited, 15% otherwise |
| Real word | At most one. Usually at the end, as a question or exclamation; one time in five at the start, as an announcement. Curious always asks, at the end |
| Randomness | Seeded per line, so replaying a line in debug mode gives the same sound |

**Feeling shapes the syllables and the tune.** These are the eight feelings
`say` accepts:

| Feeling | Syllables | Rhythm | Tune |
| --- | --- | --- | --- |
| Happy | Bright `a` and `i`, lots of doubling | Bouncy | `bounce` |
| Excited | Like happy, faster and longer | Fast | `bounce` |
| Proud | Open `a` and `o`, a long last syllable | Steady, then a flourish | `lift` |
| Curious | Ends in `i` or `e` | Hesitant, a pause before the word | `up` |
| Hopeful | Soft `o` and `u` | Small and slow | `up` |
| Annoyed | Clipped `t`, `k` and `p` | Short and punchy | `flat` |
| Sad | Rounded `u` and `o`, trailing off | Slow | `down` |
| Sleepy | Hums `mm` and `nn`, and soft `mu`, `mo`, `nu`, `no` | Very slow, may trail off mid-line | `down` |

Examples, with the word in bold (these show the shape only):

- happy: *"ba-ba ti-pa… **done**!"*
- curious: *"mi-ne? po… **tests**?"*
- annoyed: *"tu-ka. pa-ka tu… **build**."*
- sleepy: *"mmn… mu-no…"*
- hopeful: *"nu-po… **food**?"*

When you mumble at Boop, it answers with its own gibberish at the same
energy. It doesn't copy your sounds.

## 5. Delivery

| Setting | Comes from |
| --- | --- |
| Base pitch | Fixed at 100%. Mood used to move it; mood is parked ([FUTURE.md](FUTURE.md)). Sweet or cheeky doesn't change it in v1 |
| Tune | The feeling (§4): `up`, `down`, `bounce`, `flat` or `lift` |
| Tempo | 135 ms per syllable, then by feeling (excited −20, happy and annoyed −10, hopeful +10, sad +25, sleepy +35), kept within 90–180 ms (*proposed*) |
| Liveliness | ±5% random pitch and ±10% timing per syllable, so it never sounds robotic |
| Volume | The app's volume setting. Silent when muted |

## 6. The real word

The device can't synthesise speech, so the real word always comes from a
fixed **vocabulary** of about 40 words (*proposed*):

- **Topic words:** `tests`, `build`, `docs`, `deploy` (the topic tags from
  [ADAPTERS.md](ADAPTERS.md) §3), plus `bug`.
- **Interjections:** `yay`, `oops`, `hmm`, `finally`, `done`, `food`,
  `sleepy`, `hi`, `bye`, `love`, and a few more.

The v1 list has 40 words: `tests build docs deploy bug fix ship code merge
review yay oops hmm finally done food sleepy hi bye love wow yes no nope
okay again nice ugh boo whee hooray thanks hello more snack nap play good
oh what`.

The vocabulary is English everywhere in v1. The gibberish needs no
translation, and a stray English word is part of the charm. The same list is
the multiple-choice `word` field in the `say` tool
([HARNESS.md](HARNESS.md) §6), so the brain can't ask for a word Boop can't
say. Adding a word is a firmware asset change and ships as an announced
update.

## 7. Staying unintelligible

Every generated line is checked before it's sent. A line fails if any
gibberish word, or the whole line read without hyphens:

- is a real word of three or more letters in the Mac's English word list
  (`/usr/share/dict/words`);
- is on a short list of rude or sensitive words in our launch languages
  (English, Korean, Japanese and romanised Chinese);
- is a known Minion word or catchphrase.

A doubled syllable (`po-po`, `ki-ki`) is the Minion bounce, and the
Mac's word list is full of obscure doubles (`kiki`, `pipi`, `baba`), so
doubles skip the word list. A short list of doubles people hear as words
(`mama`, `papa`, `nana`, `yoyo` and a few more) still fails, as do nursery
words for the toilet (`kaka`, `pipi`). Rude and Minion words of four or
more letters also fail anywhere inside the line, across word breaks.

While building a line, Voice re-rolls a gibberish word that fails, up to 4
times. The finished line is checked again. A failed line is regenerated,
up to 5 times, and then replaced with a safe hum (`mm-nn…`). The real word
is the only part allowed through, and it must come from the vocabulary; a
word outside it is left out. In a test of 10,000 lines across 25
dialects, 4 came out as the safe hum (2026-09-26).

## 8. Sound on the device

- **Assets.** The syllables and words are synthesised offline by a build
  tool and processed to sound small and chiptune. Synthesis is cheaper to
  iterate on than a recorded voice, and the 8-bit processing hides most of
  the difference. The result is a fixed, versioned asset pack, so Boop's
  voice only changes with an announced update.
- **Size.** Each syllable is one short 8-bit sample at 11.025 kHz. The
  budget was about 2 KB per syllable and 6 KB per word, roughly 360 KB; the
  v1 pack is 226 KB (64 syllables of 84–163 ms, 40 words of 125–481 ms).
- **How they're made.** `tools/voicegen/voicegen.py` reads the syllable set
  and vocabulary from `Sounds.swift`, synthesises syllables with macOS's
  Italian voice (Alice), so vowels stay pure (a few are respelled: `ki` →
  `chi`, `ge` → `ghe`, `ya` → `ia`), and words with an English one
  (Samantha). It trims them, pitches them up (1.3× for syllables, 1.15× for
  words), saturates and normalises them, and writes
  `firmware/assets/voice.h`. The hums `mm` and `nn` aren't hummed by `say` (it
  gives 0.85 s of speech, most likely the letter names), so they're
  synthesised as a nasal tone. `--wav-dir`
  writes every clip as a WAV for listening.
- **Playback.** Pitch and tempo are changed in software, by resampling each
  syllable as it plays. It's the same trick Animal Crossing uses. Each
  syllable gets one beat of `ms` and the word two; a clip longer than its
  beat is cut with a 5 ms fade, and a long word speeds up to fit (at most
  1.6×). The base pitch is fixed (§5), the tune bends it across the line, and the ±10% timing moves within pairs of
  beats, so a line lasts exactly beats × `ms`, the same time the mouth
  moves. A syllable the device doesn't know keeps its beat, silent. The sound
  cue (the needs-you chirp) is a synthesised tone. It only comes with
  "needs you", which already stops any line.
- **Limits.** The device clamps `ms` to 60–400 and the base pitch to
  60–160%, and plays at most 12 syllables of a line.
- **On screen.** The mouth follows the syllables, open on vowels and closed
  on `m`, `b` and `p`. The bubble shows only the real word, with small
  squiggles for the gibberish around it. With the sound off, the bubble and
  mouth still play.
- **Checking it.** Tests check playback through `dbg.state`
  ([VERIFICATION.md](VERIFICATION.md) §3). The sound itself is checked by
  ear on the bench board's speaker ([DEVICE.md](DEVICE.md) §3):
  `tools/boopctl mumble`, `say`, `volume` and `sound` play it on demand
  ([VERIFICATION.md](VERIFICATION.md) §2).

## 9. How often Boop talks

Mumbles are occasional. Beyond reactions to events, Boop mutters about once
every 2–4 minutes while agents work (*proposed*). It never mumbles while
something needs you, and it's silent in quiet mode
([BEHAVIORS.md](BEHAVIORS.md)).
