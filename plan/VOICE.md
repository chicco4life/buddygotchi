# Boop: voice

Updated 2026-09-25. How Boop's gibberish is built, how it sounds, and how we
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

Voice's interface is one function:

```
line(feeling, word?, mood, dialect) -> { syllables, word, word_position, tune, ms_per_syllable }
```

## 3. The syllables

**Sounds we use:** soft, rounded consonants and pure open vowels, which is
where the Minion bounce comes from.

- Consonants: `b p m n d t l k g y w`
- Vowels: `a e i o u`, always pronounced as in Italian
- Shapes: mostly consonant + vowel (`ba`, `mi`, `po`), sometimes ending in
  `n` or `m` (`pan`, `tum`), and sometimes a bare vowel (`a`, `o`) for gasps
  and trailing off

**Sounds we avoid:** `s`, `sh`, `f`, `th`, `r` and `v`. They make gibberish
sound like real speech and are hard to play cleanly on an 8-bit speaker.

**The full set** is about 60 syllables, fixed in the firmware.

**Each Boop's dialect.** At setup, Boop's random seed picks about 16
favourite syllables from the full set. Most lines use the favourites, with
the rest of the set coming in occasionally. The dialect never changes, so
your Boop always sounds like itself.

## 4. Building a line

A line is 2–8 syllables, grouped into gibberish "words" of 1–3 syllables:

```
 ma-po  li  bu-da…  tests?
 └─ gibberish ─────┘ └ real word
```

| Part | Rule |
| --- | --- |
| Length | Voice picks short (2–4 syllables) or long (5–8), from the feeling and Boop's energy |
| Grouping | Groups of 1–3 syllables. Doubling is common (`po-po`, `ba-ba`), because it sounds playful |
| Real word | At most one. Usually at the end, as a question or exclamation; sometimes at the start, as an announcement |
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
| Sleepy | Hums: `m`, `n`, `mu`, `nn` | Very slow, may trail off mid-line | `down` |

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
| Base pitch | Boop's energy; a cheeky Boop sits a little higher than a sweet one |
| Tune | The feeling (§4): `up`, `down`, `bounce`, `flat` or `lift` |
| Tempo | Mood; 90–180 ms per syllable (*proposed*) |
| Liveliness | ±5% random pitch and ±10% timing per syllable, so it never sounds robotic |
| Volume | The app's volume setting. Silent when muted and in focus mode |

## 6. The real word

The device can't synthesise speech, so the real word always comes from a
fixed **vocabulary** of about 40 words (*proposed*):

- **Topic words:** `tests`, `build`, `docs`, `deploy` (the topic tags from
  [ADAPTERS.md](ADAPTERS.md) §3), plus `bug`.
- **Interjections:** `yay`, `oops`, `hmm`, `finally`, `done`, `food`,
  `sleepy`, `hi`, `bye`, `love`, and a few more.

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

A failed line is regenerated, up to 5 times, and then replaced with a safe
hum (`mmn…`). The real word is the only part allowed through, and it must
come from the vocabulary.

## 8. Sound on the device

- **Assets.** The syllables and words are synthesised offline by a build
  tool and processed to sound small and chiptune. Synthesis is cheaper to
  iterate on than a recorded voice, and the 8-bit processing hides most of
  the difference. The result is a fixed, versioned asset pack, so Boop's
  voice only changes with an announced update.
- **Size.** Each syllable is one short 8-bit sample. About 60 syllables at
  about 2 KB, plus about 40 words at about 6 KB, comes to roughly 360 KB,
  which fits comfortably in the firmware.
- **Playback.** Pitch and tempo are changed in software, by resampling each
  syllable as it plays. It's the same trick Animal Crossing uses.
- **On screen.** The mouth follows the syllables, open on vowels and closed
  on `m`, `b` and `p`. The bubble shows only the real word, with small
  squiggles for the gibberish around it. With the sound off, the bubble and
  mouth still play.
- **Bare board.** The v1 board has no speaker ([DEVICE.md](DEVICE.md) §3).
  Everything still runs, and tests check playback through `dbg.state`
  ([VERIFICATION.md](VERIFICATION.md) §3). The sound itself is checked by
  ear once a speaker is attached.

## 9. How often Boop talks

Mumbles are occasional. Beyond reactions to events, Boop mutters about once
every 2–4 minutes while agents work (*proposed*). It never mumbles while
something needs you, and it's silent in quiet and focus mode
([BEHAVIORS.md](BEHAVIORS.md)).
