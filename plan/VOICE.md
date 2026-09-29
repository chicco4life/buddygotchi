# Boop: voice

Updated 2026-09-29. What Boop says, how the brain and Voice pick it, and
how the device plays it, with the sound effects that go with the face's
designs (§10). The code is the source: `app/BoopKit/Voice/` on the Mac,
`firmware/src/voice/`, `firmware/src/app/effect_track.*` and
`firmware/src/board/audio.*` on the device, and
`internal/tools/voicegen/` and `internal/tools/sfxgen/` for the sounds.

## 1. What we're after

Boop half-speaks. Now and then it huffs, grunts or gasps, says a word
that lands ("Go", "Done", "Again"), names what's going on ("Tests",
"Search"), and at a big moment a little catchphrase ("Mamma mia",
"Tiny genius"). When a failure really stings it swears at it. It never
talks in sentences: at most a feeling and a topic, "Pfft... Test".

- **Emotion first.** Every take was performed in one of Boop's moods, so
  you can tell happy, annoyed or whiny with your eyes closed.
- **Always the face's mood.** A take plays only in the face it was
  recorded for, never borrowed from another mood's voice. Every face has
  takes for every feeling and every topic (§3), so Boop can always say
  something.
- **One voice.** Every take is the same recorded voice, the bank's
  "Robot Minion 1", in one texture, so Boop sounds like one creature.

## 2. Who does what

| Step | Done by |
| --- | --- |
| Decide what Boop says: how it feels (`say.feeling`), what NOW is about (`say.about`) and how big (`say.kind`) | The brain, in the `react` action's questions ([harness/DECISIONS.md](harness/DECISIONS.md) §3, §5) |
| Find a take for each answer, in the face's mood, fit for the turn's finish, of the nearest kind, and join them into a line (§4) | Voice, on the Mac |
| Send it | The device link, as a `moment`'s `say`: `{"take":"previous.pfft","then":"phase1.word.test.test__annoyed__contained"}`, one take without `then`, or `{}` for nothing ([PROTOCOL.md](PROTOCOL.md) §3) |
| Play it whole from the SD card, with the mouth and bubble in time | The device (§8) |

Voice is the only code that knows what Boop can say. The brain never
picks a recording: it picks from three feelings, fifteen topics and four
kinds, and Voice maps them onto however many takes there are. So the
brain's questions stay the same size as the bank grows.

## 3. The takes

The takes come from Federico's recorded voice bank,
[internal/boop-design/assets/boop-voice-v1/](../internal/boop-design/assets/boop-voice-v1/README.md):
2,722 recordings of one ElevenLabs voice, each a word, a sound, a phrase
or a swear, performed in one mood; about 45 minutes in all. The repo
keeps only the robot-soft texture's WAVs. None has been approved by ear:
the owner chose to ship them all as the bank sorts them (2026-09-29).

| Kind | Takes |
| --- | --- |
| `sound` | 319: huffs, grunts, sighs and gasps (Tsk..., Hrr..., Aww..., Phew..., Hm?) |
| `word` | 2,230: a word in each mood it fits (Go, Done, Again, Test, Search, Drat, Basta, Yatta) |
| `phrase` | 155: Mamma mia, Oh no, Nailed it, Moment of truth, Bada bing bada boom… |
| `swear` | 18: Shit, Fuck, Damn, Crap and Shiba, in annoyed, irritated and grumpy |

**Two parts.** Every take answers one of the brain's two questions, by
the bank's intent (voicegen's `FEELING` and `ABOUT`):

| Part | Answer | The bank's intents |
| --- | --- | --- |
| feeling | `upset` | frustration (the swears included), setback, deflate |
| | `glad` | celebrate, delight, relief, pride, insight |
| | `tickled` | poke |
| about | `start` | begin |
| | `helpers`, `helper back` | delegate, return |
| | `retry`, `work`, `tests` | retry; work and effort; test |
| | `command`, `tool` | terminal, tool |
| | `looking`, `planning` | search, analyze and ponder; plan |
| | `done`, `answer` | success, reply |
| | `stopped`, `waiting`, `quiet` | stop, wait, idle |
| needs you's | `attention` | attention: the rules', never a reaction's (§7) |

"Passed" is the one word moved: it's about `tests`, not `done`.

**Every face can say everything.** Each of the 13 faces has at least
four takes for every feeling and every topic. The one gap is on
purpose: glad in a bad mood (annoyed, irritated, grumpy, whiny, wounded,
sad) is only relief ("Phew..."), which plays only on a success.

**Finishes.** A take the bank says needs a confirmed success (a
celebration, relief, Done, Fixed, Passed) plays only on a success, and
the swears only on a failed turn.

**Moods.** Six takes were recorded in moods Boop doesn't have; by the
owner's word they're used in the nearest: relieved and amused in happy,
weary in whiny, and the two with none, Go in calm and Oi in curious.

**The assets.** `internal/tools/voicegen/voicegen.py` converts every
take in the bank's manifest from its robot-soft WAV (8-bit, 11.025 kHz):
the near-silence around it trimmed (10 ms frames quieter than −45 dBFS,
keeping 30 ms before the first sound and 80 ms after the last),
saturated and normalised so it's as loud on the small speaker, and
stored as 8-bit samples. The robot-soft texture is already low-passed at
4.2 kHz, so 11.025 kHz keeps all of it. It writes two files:

- `.build/voice/voice.bin`, the **voice pack**, built rather than
  checked in (`make -C internal voice`): each take's id, bubble text,
  samples and mouth, open or shut every 20 ms (open while a frame is at
  least a fifth as loud as the take's loudest), with a version (§8).
  The board plays it from its SD card; the simulator and the tests read
  this file.
- `app/BoopKit/Voice/Takes.swift`, checked in: each take's id, text,
  part, answer, kind, mood, the finish it needs and its length, which
  Voice picks from, and the pack's version. It's written as one
  `append` per take, in functions of 400: a single array literal of
  every take makes the Swift compiler run out of memory. A test holds it
  to the pack.

The 2,722 are 0.46–2.61 s once trimmed, 45 minutes in all: a 30.5 MB
pack. Adding a take means adding it to the bank, rerunning voicegen and
copying the pack onto the card; the firmware doesn't change.

## 4. What a reaction says

`Voice.line(feeling:about:kind:face:finish:avoiding:)`, with
`Voice.take` for each part:

1. For the feeling, then the topic: the takes of that answer, performed
   in the face's mood, whose finish fits (a success take only when
   `react.animation` is `success`, a swear only when it's `failure`).
2. Of those, the kind asked for; with none of it, the nearest kind,
   plainer before fancier at the same distance (a sound asked for is a
   word before a phrase), but never a swear nobody asked for.
3. At random among them, but not one of the last line's takes while
   another fits.
4. The line is the feeling's take, then the topic's, 180 ms apart
   (`Voice.joinGapMs`). A phrase plays alone, and so does the feeling's
   take when the two would run past 2.8 s (`Voice.maxLineMs`). With
   neither, Boop says nothing, and the face plays on its own.

Real lines, from `boopdev say`: upset about tests, a sound, in an
annoyed face is "Pfft Validate"; upset in a swear in an irritated face
at a failed turn is "Shit", and with no failure the nearest plainer
kind, "Oh, come on"; work in a sound in an engaged face is "Krr...";
glad in a word in a happy face with no success is a sound, "Ha!"; glad
in a grumpy face with no success is nothing.

The brain's side is in [harness/DECISIONS.md](harness/DECISIONS.md) §3:
`say.feeling` and `say.about` offer only the answers that have a take,
naming the faces that can say one when not all of them can. The
steering asks Boop to say something almost always.

## 5. Volume

**Volume** is the app's setting, 0–10, sent in every `state`; 0 is
silent. Takes play at their recorded pitch and speed: nothing is
retuned, hurried or cut to fit.

## 6. Words, phrases and swears

Boop is no longer held to one English word in gibberish (the rule until
2026-09-29). Borrowed words (Dai, Basta, Aigo, Yatta) and the phrases
play like any take. Phrases are for moments worth remembering, and the
steering keeps them rare. Swears are for a failed turn that really
stings, said at the situation, never at the person; the code allows one
only on a failure (§4), the steering gives a failed turn an irritated
face, which has them, and each personality says how much Boop swears
([harness/DECISIONS.md](harness/DECISIONS.md) §2.2): boop at a stinging
failure, chatter at every failed turn. Sad and wounded have no swears:
an agent giving up gets a sigh.

## 7. What Boop never says

- Nothing while something needs you: the ding is needs you's only sound
  (§9, [BEHAVIORS.md](BEHAVIORS.md) §3.2). The bank's needs-you takes
  (Hello, Oi, Knock knock) are in the pack but no reaction says them.
- Nothing while the mic is on.
- No take borrowed from another mood, and none made up: when the bank
  has nothing for the face, Boop is silent.
- Nothing when the board's card has another pack, or none (§8).

## 8. Sound on the device

**The card.** Every take is on the board's microSD card, as the voice
pack at `/boop/voice.bin` ([DEVICE.md](DEVICE.md) §2), which
`voicegen.py --card /Volumes/<card>` copies onto a card in the Mac, in
seconds. With no card reader, `boopctl card` copies it over USB
(`dbg.card`), resuming where it stopped, but at about 0.7 KB/s, hours for
the whole pack. The
board mounts it at boot and reports the pack's version in `status` and
`dbg.ping` (`none` with no card or no pack), and whether the card is
there as `dbg.ping`'s `card` ([PROTOCOL.md](PROTOCOL.md) §4–5). The Mac
sends takes only while that version is its own `Take.packVersion`;
otherwise Boop has no voice, and says so once in `boop.log`. Its faces
and sound effects carry on: the effects stay in flash.

**The pack**, little-endian: a 64-byte header (`BOOPVOX1`, the version,
the number of takes, the record size, where the index starts, the rate
and the mouth's frame), then an index of 128-byte records sorted by id
(the id, the bubble's text, where its samples and mouth are and how
long), then each take's mouth, a byte per 20 ms, and its samples. The
device finds a take by binary search of the index, a dozen reads,
without holding the index, and keeps the last eight it looked up
(`voice::takeIndex`).

**Playback.** A line's takes are looked up when its moment arrives, and
the audio task plays them whole, from first sample to last, at their
recorded pitch: the 11.025 kHz samples are read from the card a
kilobyte at a time and interpolated to the DAC's 22.05 kHz
([DEVICE.md](DEVICE.md) §4). Between two takes, 180 ms of silence. A
take the pack doesn't have plays nothing. A line cut short (hushed, or
replaced by a new one) fades out over 4 ms under what comes next, so
the cut doesn't click.

**The mouth** follows each take's mouth frames: open while it's loud,
shut in its pauses and between the two. **The bubble** shows the line's
words, from when it starts until 1.2 s after it ends, in the bottom lane
in the status strip's place ([DEVICE.md](DEVICE.md) §4). With the sound
off, the mouth and bubble still play.

**Checking it.** Tests check the timeline through `dbg.state`'s `audio`
([PROTOCOL.md](PROTOCOL.md) §5). The sound itself is checked by ear on
the bench board's speaker ([DEVICE.md](DEVICE.md) §3):
`internal/tools/boopctl takes` plays every take from the card, and
`internal/tools/boopctl play needs` plays needs you's alert
([VERIFICATION.md](VERIFICATION.md) §2).

## 9. How often Boop talks

When Boop reacts, and when it mustn't, is in [BEHAVIORS.md](BEHAVIORS.md)
§2, §4 and §6; whether it says something is the brain's and Voice's
(§4). On the device, a `state` with "needs you" or volume 0 stops a line
that's playing.

**When a line starts.** A line on its own plays at once, over whatever
face shows. A line that comes with an animation, as the brain's finish
sends one, starts at that design's voice window (§10), so it follows the
design's attention cue rather than talking over it; its sound, mouth and
bubble start together. The animation holds on, resting on its last
frame, until the line and its bubble end. A tap or "needs you" before
the window drops the line unplayed. The Mac reckons the same length for
the moment (`DeviceMoment.playMs`, from `FaceLoops.voiceMs`). A reaction
that says nothing keeps the next reaction from replacing its face for as
long as a bubble would show, 1.2 s (`DeviceMoment.faceFirstMs`).

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
  the tool takes the square root: the loudest event plays about as loud
  as a take, the quietest at about a tenth of that, and the order holds.
- The bank's pitch for an event (0.91–1.12) is kept, and the device
  resamples the clip for it.

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
| task_complete, error | First loop only | The fanfare, or a failure's sputter (never a trophy), then room for a take |
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

**With a take.** Effects mix under the voice and don't stop it. While a
take plays they are a quarter as loud, the bank's level, except needs
you's, the finish's and an error's: the design decides, not the clip.
No take plays while something needs you (§7), so the ding is always
heard. It is the only needs-you sound: a new request shown plays the
performance again from its start ([BEHAVIORS.md](BEHAVIORS.md) §3.2).
Each design also has a voice window, by the bank's `voiceStart`: when a
take over it may start, 0.12 s after the last attention cue ends for
needs you, the finish and an error, and 0.45 s in for the rest. facegen
works it out for every design (`bank.mjs`; the bank's own `voiceWindows`
gives it only for the new moods') and lists it in its manifest; sfxgen
writes it into sfx.h (`voice::Score::voiceMs`), where the device starts
a take that comes with an animation (§9), and facegen into the Mac's
`FaceLoops` (`voiceMs`).

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
