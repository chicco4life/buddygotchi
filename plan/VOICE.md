# Boop: voice

Updated 2026-09-29. How Boop's gibberish is built on the Mac, kept
unintelligible, and played on the device, and the sound effects that go
with the face's designs (§10). The code is the source:
`app/BoopKit/Voice/` on the Mac, `firmware/src/voice/`,
`firmware/src/app/effect_track.*` and `firmware/src/board/audio.*` on the
device, and `internal/tools/voicegen/` and `internal/tools/sfxgen/` for
the sounds.

## 1. What we're after

Boop sounds like a Minion from the films: fast, bouncy and full of
feeling, with not a word you can make out, except that now and then one
real English word pops out and lands, like *"…tests?"*.

- **Emotion first.** You can tell happy, annoyed, sleepy or curious with
  your eyes closed.
- **Unintelligible.** Nothing but the one real word sounds like English,
  or like any language you speak.
- **Recognisably this Boop.** Each Boop has its own favourite sounds, so
  two side by side sound related but not the same.

We take the feel of Minion speech (open vowels, a bouncy rhythm, a
pseudo-Romance lilt), never its words or catchphrases, which belong to
the films.

## 2. Who does what

| Step | Done by |
| --- | --- |
| Decide to mumble: a feeling and maybe one word | The brain, whose `react` action picks a mood's face and the word; Voice gives the face its feeling (§4, [harness/DECISIONS.md](harness/DECISIONS.md) §5) |
| Build the line (syllables, where the word goes, tune and tempo) and check it isn't accidentally a word (§7) | Voice, on the Mac |
| Send it | The device link, as a `moment`'s `say` ([PROTOCOL.md](PROTOCOL.md) §3) |
| Play it, with the mouth in time | The device (§8) |

Voice is the only code that knows what Minion speech is. The brain never
writes syllables: it picks a face and at most one word from a fixed
list. So the voice is the same whichever brain is in use, and no model
can slip real words into the gibberish.

Voice is made once per Boop, from its dialect (§3), and has one function,
plus the feeling each mood's face mumbles in (§4):

```
Voice(dialect)
  line(feeling, word?, seed) -> { groups, word, at, tune, ms }
Voice.feeling(forMood: mood) -> feeling
```

`groups` are the gibberish words, each a list of syllables; `at` is where
the word goes, as an index into the syllables; `ms` is milliseconds per
syllable. The same inputs always give the same line. `react` counts its
seeds up from 1, so a run is repeatable, and
`boopdev voice FEELING|MOOD [WORD] --seed N` rebuilds any line
([VERIFICATION.md](VERIFICATION.md) §2).

## 3. The syllables

Soft, rounded consonants and pure open vowels are where the bounce comes
from: `b p m n d t l k g` (and `y`, `w` in glides), and `a e i o u`,
always said as in Italian. There's no `s`, `sh`, `f`, `th`, `r` or `v`:
they make gibberish sound like real speech and don't play cleanly on an
8-bit speaker.

The full set is 64 syllables, fixed in the firmware, with
`app/BoopKit/Voice/Sounds.swift` as the source:

- the 45 pairs of `b p m n d t l k g` with `a e i o u`;
- the glides `ya yo yu wa we wo`;
- the bare vowels `a e i o u`, for gasps and trailing off;
- six closed syllables that aren't English words: `pum lon kun tem gom lun`;
- two hums, `mm` and `nn`, for sleepy lines and the safe hum (§7).

**Each Boop's dialect.** Boop's random seed, made at setup and kept in
`long-term.md` ([ARCHITECTURE.md](ARCHITECTURE.md) §4.2), picks 16
favourite syllables from the set (not the hums). About 70% of a line's
syllables come from the favourites that suit the feeling, and the rest
from all the syllables that suit it. The dialect never changes, so your
Boop always sounds like itself.

## 4. Building a line

A line is 2–8 syllables, grouped into gibberish "words" of 1–3, plus at
most one real word:

```
 ma-po  li  bu-da…  tests?
 └─ gibberish ─────┘ └ real word
```

- **Length.** Short (2–4 syllables) or long (5–8); how often it's long
  depends on the feeling (below).
- **Grouping.** A quarter of the words have one syllable, half two and a
  quarter three. A two-syllable word is often a double (`po-po`,
  `ba-ba`), which sounds playful: 40% of the time for happy and excited,
  15% otherwise.
- **The real word.** At most one, from the vocabulary (§6). Usually at the
  end, as a question or an exclamation; one time in five at the start, as
  an announcement. Curious always asks, at the end. A word that isn't in
  the vocabulary is left out.

The feeling picks the syllables, how often the line is long, the tempo
and the tune (§5). There are eight feelings:

| Feeling | Syllables | Long lines | ms a syllable | Tune |
| --- | --- | --- | --- | --- |
| Happy | Bright `a` and `i`, lots of doubles | 45% | 125 | `bounce` |
| Excited | Like happy | 80% | 115 | `bounce` |
| Proud | Open `a` and `o`, ending on `lon`, `gom`, `a` or `o` | 50% | 135 | `lift` |
| Curious | Any open syllable, ending in `i` or `e` | 30% | 135 | `up` |
| Hopeful | Soft `o` and `u` after `m n l y w b` | 25% | 145 | `up` |
| Annoyed | Clipped `t`, `k` and `p` | 20% | 125 | `flat` |
| Sad | Rounded `u` and `o`, ending on a bare `u` or `o` | 30% | 160 | `down` |
| Sleepy | The hums, and `mu mo nu no` | 10% | 170 | `down` |

**The brain's reactions** are the 13 moods' faces
([harness/DECISIONS.md](harness/DECISIONS.md) §3), and each mumbles in a
feeling (`Voice.feeling(forMood:)`): happy, excited, proud, curious,
annoyed and sad in the feeling of the same name. The moods with no
voice of their own yet borrow the nearest one until their recorded
voice arrives: calm mumbles in happy's, engaged in curious's, grumpy
and irritated in annoyed's, whiny and wounded in sad's, and determined
in the temporary default, happy's. The audio is still being tuned, and
the face is what the reaction means. Only the tools use hopeful and
sleepy (`boopctl mumble`, `boopdev voice`, which also takes a mood and
plays its feeling).

| Mood | Feeling |
| --- | --- |
| happy, calm, determined | happy |
| excited | excited |
| proud | proud |
| curious, engaged | curious |
| annoyed, irritated, grumpy | annoyed |
| sad, whiny, wounded | sad |

Real lines, from `boopdev voice FEELING [WORD] --seed N` with its
default dialect (`7f3a`): happy `done` (seed 2) *"la-la la… done!"*,
curious `tests` (seed 3) *"bu lo-lo ki… tests?"*, annoyed `build`
(seed 1) *"build! pi ko-ko…"*, hopeful `food` (seed 1) *"yo-lun… food?"*,
and sleepy (seed 3) *"mu-nu-mu…"*.

## 5. Delivery

**Tempo** is 135 ms a syllable at the neutral pace, moved only by the
feeling (§4) and kept within 90–180 ms. The personality and its nature
(sweet or cheeky) don't change the voice.

**Tune** is the feeling's pitch shape across the line, the word's beat
included. The real word bends half as far, so it stays closer to its own
voice.

| Tune | Pitch across the line |
| --- | --- |
| `up` | Rises from 1× to 1.25×, with the last beat 0.1× higher still |
| `down` | Falls from 1.1× to 0.8× |
| `bounce` | Alternates 1.1× and 0.95× |
| `lift` | Level at 1×, then 1.25× on the last beat |
| `flat` | Level at 0.98× |

**Liveliness** is ±5% random pitch and ±10% timing on each beat, so it
never sounds robotic, with the line's length kept exact (§8). The device
seeds it per line.

**Volume** is the app's setting, 0–10, sent in every `state`; 0 is
silent.

## 6. The real word

The device can't synthesise speech, so the real word always comes from a
fixed vocabulary of 42 English words (`Sounds.vocabulary`):

- **Topic words:** `tests build docs deploy` (the topic tags from
  [ADAPTERS.md](ADAPTERS.md) §3), `bug fix ship code merge review`, and
  the agents' names, `claude codex`.
- **Interjections:** `yay oops hmm finally done food sleepy hi bye love
  wow yes no nope okay again nice ugh boo whee hooray thanks hello more
  snack nap play good oh what`.

The brain's word questions offer seventeen of them, eight exclamations
and nine topic words: the four tags; `bug`, `merge` and `review`, which
Jev reads from your prompt and the agent's last message; and the agent's
name, the filler when no other topic fits
([harness/DECISIONS.md](harness/DECISIONS.md) §3), so
it can't ask for a word Boop can't say. The vocabulary is English
everywhere: the gibberish needs no translation, and a stray English word
is part of the charm. Adding a word means adding it to `Sounds.swift`,
regenerating the assets (§8) and reflashing.

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
those from the word list, about a tenth of it. Without the word list,
only the fixed lists apply.

While building a line, Voice re-rolls a gibberish word that fails, up to 4
times, then checks the finished line. A line that fails is built again, up
to 5 times, and then replaced with the safe hum, `mm-nn…`, tune `down`.
The real word isn't checked: it's meant to be heard. `VoiceTests` builds
10,000 lines across 25 dialects and checks them against the lists on its
own: none may fail, and fewer than 50 may end as the safe hum.

## 8. Sound on the device

**The assets.** Every syllable and word is synthesised offline and made
to sound small and chiptune, into a fixed, versioned pack, so Boop's
voice only changes when the pack is rebuilt and flashed.
`internal/tools/voicegen/voicegen.py` reads the syllables and vocabulary
from `Sounds.swift` and writes `firmware/assets/voice.h`, with a version
that `dbg.ping` reports ([PROTOCOL.md](PROTOCOL.md) §5):

- Syllables are spoken by macOS's Italian voice (Alice), so vowels stay
  pure; some are respelled so Italian reads them as meant (`ki` → `chi`,
  `ge` → `ghe`, `ya` → `ia`). Words use an English voice (Samantha).
- Each clip is trimmed, pitched up (1.3× for syllables, 1.15× for words,
  so the word stays clear), saturated and normalised, and stored as 8-bit
  samples at 11.025 kHz.
- `say` can't hum `mm` or `nn`, so the hums are synthesised as a nasal
  tone.

The pack is 235 KB: 64 syllables of 84–163 ms and 42 words of 125–481 ms.

**Playback.** The device looks each clip up by name and resamples it as it
plays, so pitch and tempo change without new assets (the trick Animal
Crossing uses), then feeds the DAC at 22.05 kHz from a task of its own
([DEVICE.md](DEVICE.md) §4).

- Each syllable gets one beat of `ms` and the word two. A clip longer
  than its beat is cut with a 5 ms fade, and a long word speeds up to fit,
  by at most 1.6×.
- The timing jitter (§5) moves within pairs of beats, so a line lasts
  exactly beats × `ms`.
- A syllable the device has no clip for keeps its beat, silent. A word it
  has no clip for isn't played.
- The device clamps `ms` to 60–400 and plays at most 12 syllables of a
  line.
- A line cut short (hushed, or replaced by a new line) fades
  out over 4 ms under what comes next, so the cut doesn't click.

**The mouth** opens for the first half of each beat for as long as the
sound lasts, and the bubble shows the word among squiggles until 1.2 s
after it, in the bottom lane in the status strip's place
([DEVICE.md](DEVICE.md) §4). With the sound off, the mouth and bubble
still play.

**Checking it.** Tests check the timeline through `dbg.state`'s `audio`
([PROTOCOL.md](PROTOCOL.md) §5). The sound itself is checked by ear on
the bench board's speaker ([DEVICE.md](DEVICE.md) §3):
`internal/tools/boopctl mumble` plays every feeling with and without a
word (`--levels` compares volumes), and `internal/tools/boopctl play needs`
plays needs you's alert ([VERIFICATION.md](VERIFICATION.md) §2).

## 9. How often Boop talks

When Boop mumbles, and when it mustn't, is in [BEHAVIORS.md](BEHAVIORS.md)
§2, §4 and §6. On the device, a `state` with "needs you" or volume 0 stops
a line that's playing.

**When a line starts.** A line on its own plays at once, over whatever
face shows. A line that comes with an animation, as the brain's finish
sends one, starts at that design's voice window (§10), so it follows the
design's attention cue rather than talking over it; its sound, mouth and
bubble start together. The animation holds on, resting on its last
frame, until the line and its bubble end: a line that doesn't fit is
never hurried. A tap or "needs you" before the window drops the line
unplayed. The Mac reckons the same length for the moment
(`DeviceMoment.playMs`, from `FaceLoops.voiceMs`).

## 10. Sound effects

The animation bank (DEVICE.md §6) comes with procedural sounds: each
design has a timeline of short effects, such as key clicks, paper, a
knock, a ding or a fanfare, made from oscillators and noise, never
recordings. The device plays them with the face, on its own: it knows the
mood, state and variation it draws, so no message carries them and the Mac
doesn't know about them.

**The assets.** `internal/tools/sfxgen/sfxgen.mjs` runs the bank's own
synthesiser and recipes
(`internal/boop-design/boop-sound-bank-v4/runtime/audio/`, unchanged) and
takes each design's timeline from the bank's `makeScene`, for the designs
facegen lists (`internal/tools/facegen/design/manifest.json`, so facegen
runs first). It writes `firmware/assets/sfx.h`, with a version that
`dbg.ping` reports as `fx` ([PROTOCOL.md](PROTOCOL.md) §5):

- Each of the 49 effects the timelines use is rendered once, low-passed
  and stored like the voice: 8-bit samples at 11.025 kHz, at full scale.
  They take 154 KB (the test allows 180 KB), and the timelines 48 KB. The
  new moods brought three: `knock`, their needs-you taps, `brake`
  (stopped) and `failedAttempt` (a failed finish, an error).
- An event's loudness is its clip's level times its gain in the bank.
  The bank spans about 40 dB, which an 8-bit speaker loses in its hiss, so
  the tool takes the square root: the loudest event plays as loud as a
  syllable, the quietest at about a tenth of that, and the order holds.
- The bank's pitch for an event (0.91–1.12) is kept, and the device
  resamples the clip for it, as it does a syllable.

**The voice-first mix.** The bank keeps its sounds sparse, so the voice
comes first. Idle, asleep, no app, listening and waiting are silent. A
routine design sounds at most about 30% of its contacts, in four
gestures at most, which the mix picks afresh each loop, never moving one
off its frame. The device has no bank to ask, so sfxgen bakes the bank's
picks for loops 0 to 7 (`routineEvents`, seed 53) and the device plays
loop n's as n % 8 (`voice::events`). Needs you, the finish and an error
keep their whole timeline, and play it once.

**When they play.** A design's events follow its clock, which starts
with the design (a new look, or a new animation) and runs on past its loops;
its loops are counted from its start. Each timeline has the bank's
policy:

| State | Policy | So |
| --- | --- | --- |
| working, planning, terminal, tool_use, searching, analyzing, testing | Every loop, each loop its own picks | A few clicks and rustles, never the same loop over and over |
| The same, with a loop under 3.5 s | Every other loop: loops 0, 2, 4… | Room between a short loop's accents |
| needs_you | First loop only | Its knocks or taps, ending in the ding; its pose then holds, silent |
| task_complete, error | First loop only | The fanfare, or a failure's sputter (never a trophy), then room for a mumble |
| starting, delegating, helper_return, reply_ready, stopped, poked, tap_spam | First loop only | A few contacts as it starts |
| idle, asleep, no_app, listening, waiting | Silent | |

- A change of design (another look, variation, mood or animation, or
  the looks taking turns, [BEHAVIORS.md](BEHAVIORS.md) §2) stops the
  last one's effects with a 4 ms fade. The new timeline picks up where the
  new design's clock is, so a mood changing mid-loop doesn't replay what
  the loop already passed.
- Events go to the audio task 70 ms ahead of their frame, about what the
  DAC's DMA holds, so they leave the speaker with it. An event more than
  150 ms late (a stalled loop) is dropped.
- A test pattern (`dbg.pattern`) is silent. Volume 0 stops the effects
  and sends none; volume sets their level as it does the voice's.

**With a mumble.** Effects mix under the voice and don't stop it. While a
line plays they are a quarter as loud, the bank's level, except needs
you's, the finish's and an error's: the design decides, not the clip.
No line plays while something needs you (§9), so the ding is always
heard. It is the only needs-you sound: a new request shown plays the
performance again from its start ([BEHAVIORS.md](BEHAVIORS.md) §3.2).
Each design also has a voice window, the bank's `voiceWindows`: when a
mumble over it may start, 0.12 s after the last attention cue ends for
needs you, the finish and an error, and 0.45 s in for the rest. facegen
works it out for every design (`bank.mjs`, the bank's rule, which the
bank itself only states for the new moods') and lists it in its
manifest; sfxgen checks it against the bank's for the new moods' designs
and writes it into sfx.h (`voice::Score::voiceMs`), where the device
starts a line that comes with an animation (§9), and facegen into the
Mac's `FaceLoops` (`voiceMs`).

**Mixing.** Up to four effects play at once; a fifth replaces the oldest.
The sum is added to the voice's samples and clipped. The amp stays on
for about a second after the last sound, so a working design's clicks
don't switch it on and off between them.

**Checking it.** `test_effects` checks the assets, the policies (the
quiet states silent, the routine ones thinned and picked afresh each
loop, the guarded ones played once and never turned down), the timing
and the mixer, and `test_device` the whole path to the Hal, with
`dbg.state`'s `audio.fx` ([PROTOCOL.md](PROTOCOL.md) §5). The sound
itself is checked by ear on the bench board.
