# Boop: voice

Updated 2026-09-27. How Boop's gibberish is built, kept unintelligible and
played on the device.

## 1. What we're after

Boop sounds like a Minion from the films: fast, bouncy and full of
feeling, with not a word you can make out, except that now and then one
real English word pops out and lands, like *"…tests?"*.

- **Emotion first.** You can tell happy, annoyed, sleepy or curious with
  your eyes closed.
- **Unintelligible.** Nothing but the one real word sounds like English,
  or like any language you speak.
- **Recognisably this Boop.** Each Boop has its own favourite sounds, so
  two side by side sound related but not identical.

We take the feel of Minion speech (open vowels, a bouncy rhythm, a
pseudo-Romance lilt), never its actual words or catchphrases, which belong
to the films.

## 2. Who does what

| Step | Done by |
| --- | --- |
| Decide to mumble: a feeling and maybe one word | A rule (working chatter), or the brain: Jev picks the feeling and the word, and the `react` action plays it ([harness/DECISIONS.md](harness/DECISIONS.md) §5) |
| Build the line (syllables, where the word goes, tune and tempo) and check it isn't accidentally a word (§7) | Voice, on the Mac |
| Send it to the device | `react`, through the device link, as a `moment`'s `say` ([PROTOCOL.md](PROTOCOL.md) §3) |
| Play it, with the mouth in time | The device (§8) |

Voice is the only code that knows what Minion speech is. The brain never
writes syllables: it picks a feeling and at most one word from a fixed
list. So the voice is the same whichever brain is in use, and no model can
slip real words into the gibberish.

Voice is made once per Boop, from its dialect (§3), and has one function:

```
Voice(dialect)
  line(feeling, word?, seed) -> { groups, word, at, tune, ms }
```

`groups` are the gibberish words, each a list of syllables; `at` is where
the word goes, as an index into the syllables; `ms` is milliseconds per
syllable. The same inputs and seed always give the same line, and `react`
logs each line's seed so debug mode can replay it.

## 3. The syllables

Soft, rounded consonants and pure open vowels are where the bounce comes
from: the consonants `b p m n d t l k g` (and `y`, `w` in glides), and the
vowels `a e i o u`, always said as in Italian. There's no `s`, `sh`, `f`,
`th`, `r` or `v`: they make gibberish sound like real speech and don't
play cleanly on an 8-bit speaker.

The full set is 64 syllables, fixed in the firmware, with
`app/BoopKit/Voice/Sounds.swift` as the source:

- the 45 pairs of `b p m n d t l k g` with `a e i o u`;
- the glides `ya yo yu wa we wo`;
- the bare vowels `a e i o u`, for gasps and trailing off;
- six closed syllables that aren't English words: `pum lon kun tem gom lun`;
- two hums, `mm` and `nn`, for sleepy lines and the safe hum (§7).

**Each Boop's dialect.** Boop's random seed, made at setup and kept in
`long-term.md`, picks 16 favourite syllables from the set (not the hums).
About 70% of a line's syllables come from the favourites that suit the
feeling, and the rest from all the syllables that suit it. The dialect
never changes, so your Boop always sounds like itself.

## 4. Building a line

A line is 2–8 syllables, grouped into gibberish "words" of 1–3, plus at
most one real word:

```
 ma-po  li  bu-da…  tests?
 └─ gibberish ─────┘ └ real word
```

- **Length.** Short (2–4 syllables) or long (5–8); how often it's long
  depends on the feeling (below).
- **Grouping.** A quarter of the words have one syllable, half have two
  and a quarter three. A two-syllable word is often a double (`po-po`,
  `ba-ba`), which sounds playful: 40% of the time for happy and excited,
  15% otherwise.
- **The real word.** At most one, from the vocabulary (§6). Usually at the
  end, as a question or an exclamation; one time in five at the start, as
  an announcement. Curious always asks, at the end.

The feeling picks the syllables, how often the line is long, the tempo and
the tune (§5):

| Feeling | Syllables | Long lines | ms a syllable | Tune |
| --- | --- | --- | --- | --- |
| Happy | Bright `a` and `i`, lots of doubles | 45% | 125 | `bounce` |
| Excited | Like happy | 80% | 115 | `bounce` |
| Proud | Open `a` and `o`, ending on `lon`, `gom`, `a` or `o` | 50% | 135 | `lift` |
| Curious | Mixed, ending in `i` or `e` | 30% | 135 | `up` |
| Hopeful | Soft `o` and `u` after `m n l y w b` | 25% | 145 | `up` |
| Annoyed | Clipped `t`, `k` and `p` | 20% | 125 | `flat` |
| Sad | Rounded `u` and `o`, ending on a bare `u` or `o` | 30% | 160 | `down` |
| Sleepy | The hums, and `mu mo nu no` | 10% | 170 | `down` |

The brain's `react` offers five of these: happy, excited, proud, curious
and annoyed ([harness/DECISIONS.md](harness/DECISIONS.md) §3).

Some real lines, from `boopdev voice <feeling> [word] --seed N` with its
default dialect: happy `done` (seed 2) *"la-la la… done!"*, curious
`tests` (seed 3) *"bu lo-lo ki… tests?"*, annoyed `build` (seed 1)
*"build! pi ko-ko…"*, hopeful `food` (seed 1) *"yo-lun… food?"*, and
sleepy (seed 3) *"mu-nu-mu…"*.

When you talk or mumble at Boop, it answers in its own gibberish; it never
copies your sounds.

## 5. Delivery

**Tempo** is 135 ms a syllable at the neutral pace, moved only by the
feeling (§4) and kept within 90–180 ms. Sweet or cheeky doesn't change
the voice.

**Tune** is the feeling's pitch shape across the line, the word's beat
included. The real word bends half as far, so it keeps closer to its own
voice.

| Tune | Pitch across the line |
| --- | --- |
| `up` | Rises from 1× to 1.25×, with the last beat 0.1× higher still |
| `down` | Falls from 1.1× to 0.8× |
| `bounce` | Alternates 1.1× and 0.95× |
| `lift` | Level at 1×, then 1.25× on the last beat |
| `flat` | Level at 0.98× |

**Liveliness** is ±5% random pitch and ±10% timing on each beat, so it
never sounds robotic, with the line's length kept exact (§8). **Volume**
is the app's setting, 0–10, sent in every `state`; 0 is silent.

## 6. The real word

The device can't synthesise speech, so the real word always comes from a
fixed vocabulary of 40 English words (`Sounds.vocabulary`):

- **Topic words:** `tests build docs deploy` (the topic tags from
  [ADAPTERS.md](ADAPTERS.md) §3), and `bug fix ship code merge review`.
- **Interjections:** `yay oops hmm finally done food sleepy hi bye love
  wow yes no nope okay again nice ugh boo whee hooray thanks hello more
  snack nap play good oh what`.

The brain's words come from this list: its word questions offer eleven
of them for now ([harness/DECISIONS.md](harness/DECISIONS.md) §3), so it
can't ask for a word Boop can't say, and Voice leaves out any word that
isn't on it. The
vocabulary is English everywhere: the gibberish needs no translation, and
a stray English word is part of the charm. Adding a word means adding it
to `Sounds.swift`, regenerating the assets (§8) and reflashing.

## 7. Staying unintelligible

Voice checks every line before it's sent. A line fails if any gibberish
word, or the whole line run together, is:

- an English word of three or more letters in the Mac's word list
  (`/usr/share/dict/words`);
- on a short list of rude or sensitive words in the launch languages
  (English, Korean, Japanese and romanised Chinese), which includes
  nursery words for the toilet (`kaka`, `pipi`);
- a Minion word or catchphrase;
- a double people hear as a word (`mama`, `papa`, `nana`, `yoyo` and a
  few more).

Rude and Minion words of four or more letters also fail anywhere inside
the line, across word breaks. A doubled syllable (`po-po`, `ki-ki`) is the
Minion bounce, and the word list is full of obscure doubles, so doubles
skip the word list, though not the other lists. Only words spelled with
the letters of Boop's syllables can ever match, so the app keeps just
those from the word list, about a tenth of it: the same answers, loaded
much faster. Without the word list, only the fixed lists apply.

While building a line, Voice re-rolls a gibberish word that fails, up to 4
times, then checks the finished line. A line that fails is built again, up
to 5 times, and then replaced with the safe hum, `mm-nn…`. The real word
isn't checked: it's meant to be heard. `VoiceTests` builds 10,000 lines
across 25 dialects and checks them against the lists on its own: none may
fail, and fewer than 50 may end as the safe hum.

## 8. Sound on the device

**The assets.** Every syllable and word is synthesised offline and
processed to sound small and chiptune, into a fixed, versioned asset pack,
so Boop's voice only changes when the pack is rebuilt and flashed.
`internal/tools/voicegen/voicegen.py` reads the syllables and vocabulary
from `Sounds.swift` and writes `firmware/assets/voice.h`:

- Syllables are spoken by macOS's Italian voice (Alice), so vowels stay
  pure; some are respelled so Italian reads them as meant (`ki` → `chi`,
  `ge` → `ghe`, `ya` → `ia`). Words use an English voice (Samantha).
- Each clip is trimmed, pitched up (1.3× for syllables, 1.15× for words,
  so the word stays clear), saturated and normalised, and stored as 8-bit
  samples at 11.025 kHz.
- `say` doesn't hum `mm` or `nn` (it gives 0.85 s of speech, most likely
  the letter names), so the hums are synthesised as a nasal tone.

The pack is 226 KB (64 syllables of 84–163 ms, 40 words of 125–481 ms).

**Playback.** The device resamples each clip as it plays, so pitch and
tempo change without new assets (the trick Animal Crossing uses), and
feeds the DAC at 22.05 kHz.

- Each syllable gets one beat of `ms` and the word two. A clip longer
  than its beat is cut with a 5 ms fade, and a long word speeds up to fit,
  by at most 1.6×.
- The timing jitter (§5) moves within pairs of beats, so a line lasts
  exactly beats × `ms`.
- A syllable the device doesn't know keeps its beat, silent.
- The device clamps `ms` to 60–400 and plays at most 12 syllables of a
  line.
- A line cut short (hushed, or replaced by a new line or the chirp) fades
  out over 4 ms under what comes next, so the cut doesn't click.
- The needs-you chirp is a synthesised 90 ms tone rising from 1.2 to
  2.4 kHz. It only comes with "needs you", which already stops any line.

**The mouth** opens and closes once a beat for exactly as long as the
sound, and the bubble shows the word among squiggles
([UX.md](UX.md) §2). With the sound off, the mouth and bubble still play.

**Checking it.** Tests check the timeline through `dbg.state`
([VERIFICATION.md](VERIFICATION.md) §3). The sound itself is checked by
ear on the bench board's speaker ([DEVICE.md](DEVICE.md) §3):
`internal/tools/boopctl mumble` plays every feeling with and without a
word (`--levels` compares volumes), and
`internal/tools/boopctl play needs` plays the chirp
([VERIFICATION.md](VERIFICATION.md) §2).

## 9. How often Boop talks

When Boop mumbles, and when it mustn't, is in [BEHAVIORS.md](BEHAVIORS.md)
§2, §4 and §6. On the device, a `state` with "needs you" or
volume 0 stops a line that's playing.
