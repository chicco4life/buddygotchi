# Boop: voice

Draft 2 · 2026-09-25. Part of the [architecture](ARCHITECTURE.md). This page
covers how Boop's gibberish is built, how it sounds, and how we keep it
unintelligible. Numbers marked *proposed* are first guesses to tune by ear.

## 1. What we're after

Boop should sound like a Minion from the films. It's fast, bouncy and full
of feeling, and you can't make out a single word, except that now and then
one real English word pops out and lands, like *"…tests?"*.

Three qualities matter most:

- **Emotion first.** You should be able to tell happy, annoyed, sleepy or
  curious with your eyes closed.
- **Unintelligible.** Nothing but the one real word should sound like
  English, or like any language you speak.
- **Recognisably this Boop.** Each Boop has its own favourite sounds, so two
  Boops side by side sound related but not identical.

We take the *feel* of Minion speech: open vowels, bouncy rhythm, a
pseudo-Romance lilt. We don't copy its actual words or catchphrases, which
belong to the films. Our syllables are our own.

## 2. Who does what

| Step | Done by |
| --- | --- |
| Decide to say something: a feeling and maybe one word | The brain or a rule, by calling the `say` action |
| Build the line: syllables, where the word goes, the tune | Voice, on the Mac, called by `say` |
| Check it isn't accidentally English | Voice |
| Send it to the device | `say`, through the device link |
| Play it | Device |

Voice is the only code that knows what Minion speech is. The brain never
writes syllables. It picks a feeling and at most one word from a fixed list,
and `say` hands both to Voice. That keeps the voice consistent across brains,
and no model can slip real words into the gibberish.

Voice's interface is one function:

```
line(feeling, word?, mood, dialect) -> { syllables, word, word_position, tune, tempo }
```

## 3. The syllables

**Sounds we use.** Soft, rounded consonants and pure open vowels, which is
where the Minion bounce comes from.

- Consonants: `b p m n d t l k g y w`
- Vowels: `a e i o u`, always pronounced as in Italian
- Shapes: mostly consonant + vowel (`ba`, `mi`, `po`), sometimes ending in
  `n` or `m` (`pan`, `tum`), and sometimes a bare vowel (`a`, `o`) for
  gasps and trailing off

**Sounds we avoid.** `s`, `sh`, `f`, `th`, `r` and `v`. They make gibberish
sound like real speech and are hard to play cleanly on an 8-bit speaker.

**The full set** is every allowed combination, about 60 syllables. It's
fixed in the firmware and never changes.

**Each Boop's dialect.** At hatching, Boop's seed picks about 16 favourite
syllables from the full set. Most lines use the favourites, and the rest of
the set comes in occasionally. The dialect never changes, so your Boop
always sounds like itself. Stage slowly widens it: a Hatchling uses
10 favourites, a Grown Boop 16, and a Veteran 20 (*proposed*).

## 4. Building a line

A line is 2–8 syllables, grouped into gibberish "words" of 1–3 syllables:

```
 ma-po  li  bu-da…  tests?
 └─ gibberish ─────┘ └ real word
```

| Part | Rule |
| --- | --- |
| Length | Short: 2–4 syllables; long: 5–8. The brain picks short or long |
| Grouping | Groups of 1–3 syllables; doubling is common (`po-po`, `ba-ba`) because it sounds playful |
| Real word | At most one. Usually at the end as a question or exclamation, sometimes at the start as an announcement |
| Tune | One contour for the whole line (§5) |
| Randomness | Seeded per line, so replaying a line in debug mode gives the same sound |

**Feeling shapes the syllables:**

| Feeling | Syllables | Rhythm |
| --- | --- | --- |
| Happy, excited | Bright `a` and `i`, lots of doubling | Fast, bouncy |
| Proud | Open `a` and `o`, longer last syllable | Steady, then a flourish |
| Curious | Ends in `i` or `e`, rising | Hesitant, a pause before the word |
| Annoyed | Clipped `t`, `k` and `p` | Short and punchy |
| Sad, tired | Rounded `u` and `o`, trailing `…` | Slow |
| Sleepy | Hums: `m`, `n`, `mu`, `nn` | Very slow, may trail off mid-line |
| Hopeful (hungry) | Soft `o` and `u`, rising at the end | Small and slow |

Examples with the word bolded, to show the shape only:

- happy: *"ba-ba ti-pa… **done**!"*
- curious: *"mi-ne? po… **tests**?"*
- annoyed: *"tu-ka. pa-ka tu… **build**."*
- sleepy: *"mmn… mu-no…"*
- hopeful: *"nu-po… **food**?"*

## 5. Tune and delivery

| Setting | Comes from |
| --- | --- |
| Base pitch | Stage: Hatchling highest, Veteran lowest. Also temperament and energy |
| Contour | Feeling: `up` (curious, question), `down` (sad, done), `bounce` (happy), `flat` (working mutter), `wobble` (worried) |
| Tempo | Mood pace; 90–180 ms per syllable (*proposed*) |
| Liveliness | ±5% random pitch and ±10% timing per syllable, so it never sounds robotic |
| Volume | The app's volume setting; muted in focus mode or when muted |

## 6. Staying unintelligible

Every generated line is checked before it's sent. If it fails, it's
regenerated, up to 5 times. After that, the line is replaced with a
guaranteed-safe hum (`mmn…`).

A line fails if any gibberish word, or the whole line read without
hyphens:

- is a word, or a close sound-alike, in an English word list (~20,000
  common words);
- is a rude or sensitive word in any of our launch languages (English,
  Korean, Japanese, Chinese romanised);
- is a known Minion word or catchphrase.

The real word is the only part allowed through, and it must come from the
vocabulary (§7).

## 7. The real word

The device can't synthesise speech, so the real word always comes from a
fixed **vocabulary** of about 40 words (*proposed*):

- topic words: tests, build, docs, bug, deploy, refactor, review…
- interjections: yay, oops, hmm, finally, done, food, sleepy, hi, bye, love…

Each word is a synthesised clip in Boop's voice, pitched like the syllables,
and shown in amber in the bubble while it plays. The same list is the
multiple-choice `word` field in the `say` tool
([HARNESS.md](HARNESS.md) §6), so the brain can't ask for a word Boop can't
say. Adding a word is a firmware asset change and ships as an announced
update.

## 8. Sound on the device

- The syllables and words are synthesised offline by a build tool, then
  processed to sound small and chiptune. The output is a fixed, versioned
  asset pack, so Boop's voice only changes with an announced update.
- Each syllable is one short 8-bit sample. Pitch is changed
  by changing the playback rate, which is free on the ESP32's DAC. This is
  the trick Animal Crossing uses.
- 60 syllables at about 2 KB each, plus 40 words at about 6 KB each, comes
  to roughly 360 KB. That fits in the ~0.8 MB asset budget.
- The mouth animation follows the syllables: open on vowels, closed on
  `m`, `b` and `p`.
- The bubble shows only the real word, with small squiggles for the
  gibberish around it. With sound muted, the bubble and mouth still play.
- The bare v1 board has no speaker ([DEVICE.md](DEVICE.md) §3). Everything
  still runs: the DAC plays, the mouth moves and the bubble shows the word.
  Tests check playback through `dbg.state` ([VERIFICATION.md](VERIFICATION.md)
  §3), and the sound itself is checked by ear once a speaker is attached.

## 9. How often Boop talks

This is covered in [BEHAVIORS.md](BEHAVIORS.md). In short, mumbles are
occasional (*proposed*: about one every 2–4 minutes of active work, at
most). They never play while something needs you, and they stop entirely
during quiet or focus mode.

## 10. Decided

- **Synthesised, not recorded.** It's cheaper to iterate on, and the
  8-bit chiptune processing hides most of the difference.
- **English only in v1.** The real word stays English everywhere. The
  gibberish needs no translation. We'll revisit for the Asian launch.
- **Mumble back matches your energy.** When you mumble at Boop, it replies
  with its own gibberish at the same energy. It doesn't copy your sounds.
