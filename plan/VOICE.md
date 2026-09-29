# Boop: voice

Updated 2026-09-29. What Boop says, how the brain and Voice pick it, and
how the device plays it, with the sound effects that go with the face's
designs (§10). The code is the source: `app/BoopKit/Voice/` on the Mac,
`firmware/src/voice/`, `firmware/src/app/effect_track.*` and
`firmware/src/board/audio.*` on the device, and
`internal/tools/voicegen/` and `internal/tools/sfxgen/` for the sounds.

## 1. What we're after

Boop half-speaks. Now and then it huffs, grunts or gasps, says one word
that lands ("Go", "Done", "Again"), and at a big moment a little
catchphrase ("Mamma mia", "Tiny genius"). When a failure really stings
it swears at it. It never talks in sentences.

- **Emotion first.** Every take was performed in one of Boop's moods, so
  you can tell happy, annoyed or whiny with your eyes closed.
- **Always the face's mood.** A take plays only in the face it was
  recorded for. When no take fits the face, Boop makes its face in
  silence rather than borrow another mood's voice.
- **One voice.** Every take is the same recorded voice, the bank's
  "Robot Minion 1", in one texture, so Boop sounds like one creature.

## 2. Who does what

| Step | Done by |
| --- | --- |
| Decide what Boop means and how to say it: a meaning (`say.meaning`) and a kind (`say.kind`) | The brain, in the `react` action's questions ([harness/DECISIONS.md](harness/DECISIONS.md) §3, §5) |
| Find a take of that meaning, in the face's mood, fit for the turn's finish, of that kind or a plainer one (§4) | Voice, on the Mac |
| Send it | The device link, as a `moment`'s `say`, `{"take":"new.d02"}`, or `{}` for nothing ([PROTOCOL.md](PROTOCOL.md) §3) |
| Play it whole, with the mouth and bubble in time | The device (§8) |

Voice is the only code that knows what Boop can say. The brain never
picks a recording: it picks from about a dozen meanings and four kinds,
and Voice maps them onto however many takes there are. So the brain's
questions stay the same size as the bank grows.

## 3. The takes

The takes come from Federico's recorded voice bank,
[internal/boop-design/assets/boop-voice-v1/](../internal/boop-design/assets/boop-voice-v1/README.md):
40 recordings of one ElevenLabs voice, each a word, a sound, a phrase or
a swear, performed in one mood. None has been approved by ear yet: the
owner chose to put all 40 on the board as they are (2026-09-29).

| Kind | Takes |
| --- | --- |
| `sound` | 10: Eh?, Tsk..., Hrr... (two), Pfft, Krr..., Rrr... tik, Heh..., Phew..., Mwahaha... |
| `word` | 23: Go (three), Work, Finish, Done (three), Yay, Yatta (two), Dai, Basta, Aigo (two), Again (four), Oi, Hello (three) |
| `phrase` | 4: Mamma mia, Bada bing bada boom, Tiny genius, Knock knock |
| `swear` | 3: Shit, Fuck, Shiba |

Each has a **meaning**, the bank's intent: `begin`, `work`, `effort`,
`ponder`, `success`, `celebrate`, `relief`, `pride`, `delight`,
`frustration`, `retry`, and `attention`, which is needs you's and never
a reaction's (§7). A take the bank says needs a confirmed success
(Finish, Done, Yay, Yatta, Phew, Bada bing bada boom, Tiny genius) plays
only on a success, and the swears only on a failure.

**Moods.** Six takes were recorded in moods Boop doesn't have; by the
owner's word they're used in the nearest: relieved (Done) and amused
(Heh) in happy, weary (Aigo, Krr) in whiny, and the two with none, Go in
calm and Oi in curious. What each face can say:

| Face | Its takes |
| --- | --- |
| calm | Go |
| happy | Finish, Done, Yay, Yatta (two), Phew, Heh |
| excited | Go, Bada bing bada boom |
| proud | Done, Tiny genius, Mwahaha |
| curious | Eh? |
| engaged | Work, Rrr... tik, Go |
| determined | Dai, Again |
| annoyed | Basta, Tsk, Pfft, Again, Shiba |
| irritated | Again |
| grumpy | Hrr (two), Mamma mia, Shit, Fuck |
| whiny | Aigo (two), Krr, Again |
| wounded | nothing |
| sad | Done |

**The assets.** `internal/tools/voicegen/voicegen.py` converts every
take in the bank's manifest from its robot-soft WAV (44.1 kHz, 16-bit):
the near-silence around it trimmed (10 ms frames quieter than −45 dBFS,
keeping 30 ms before the first sound and 80 ms after the last), cut to
11.025 kHz with a box low-pass, saturated and normalised as the old
voice's clips were so it's as loud on the small speaker, and stored as
8-bit samples. The robot-soft texture is already low-passed at 4.2 kHz,
so 11.025 kHz keeps all of it. It writes two files, both checked in:

- `firmware/assets/voice.h`: each take's id, bubble text and samples,
  and its mouth, open or shut every 20 ms (open while a frame is at
  least a fifth as loud as the take's loudest), with a version that
  `dbg.ping` reports ([PROTOCOL.md](PROTOCOL.md) §5).
- `app/BoopKit/Voice/Takes.swift`: each take's id, text, meaning, kind,
  mood, the finish it needs and its length, which Voice picks from. A
  test holds the two to the same takes.

The 40 are 0.46–2.43 s once trimmed, 42 s in all: 462,857 bytes of
samples and 2,130 of mouth. Adding a take means adding it to the bank,
rerunning voicegen, and reflashing.

## 4. Picking a take

`Voice.take(meaning:kind:face:finish:avoiding:)`:

1. The takes of that meaning, performed in the face's mood, whose
   finish fits: a success take only when `react.animation` is
   `success`, a swear only when it's `failure`.
2. Of those, the kind asked for; with none of that kind, the next
   plainer one, in the order swear, phrase, word, sound. Never a fancier
   kind than asked.
3. At random among them, but not the take said last while another fits.
4. None left: Boop says nothing, and the face plays on its own.

Real picks, from `boopdev say`: frustration, a swear, in a grumpy face at
a failed turn is Shit or Fuck; the same at a check failing mid-turn
(no failure yet) steps down to the phrase, Mamma mia; celebrate, a
phrase, in a happy face is a word, Yay or Yatta; ponder in a calm face
is nothing.

The brain's side is in [harness/DECISIONS.md](harness/DECISIONS.md) §3:
`say.meaning` offers only the meanings that have a take, and each option
names the faces that can say it, so Jev can pick a face and a meaning
that go together. The steering asks Boop to say something almost always,
which means picking such a face.

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
only on a failure (§4), and each personality says how much Boop swears
([harness/DECISIONS.md](harness/DECISIONS.md) §2.2): boop at a stinging
failure, chatter at every failed turn.

## 7. What Boop never says

- Nothing while something needs you: the ding is needs you's only sound
  (§9, [BEHAVIORS.md](BEHAVIORS.md) §3.2). The bank's needs-you takes
  (Hello, Oi, Knock knock) are on the board but no reaction says them.
- Nothing while the mic is on.
- No take borrowed from another mood, and none made up: when the bank
  has nothing for the face, Boop is silent.

## 8. Sound on the device

**Playback.** The device looks a take up by id in `voice.h` and plays it
whole, from its first sample to its last, at its recorded pitch: the
11.025 kHz samples are interpolated to the DAC's 22.05 kHz, from an
audio task of its own ([DEVICE.md](DEVICE.md) §4). A take it doesn't
have plays nothing. A take cut short (hushed, or replaced by a new one)
fades out over 4 ms under what comes next, so the cut doesn't click.

**The mouth** follows the take's mouth frames: open while the take is
loud, shut in its pauses. **The bubble** shows the take's text, from
when it starts until 1.2 s after it ends, in the bottom lane in the
status strip's place ([DEVICE.md](DEVICE.md) §4). With the sound off,
the mouth and bubble still play.

**Checking it.** Tests check the timeline through `dbg.state`'s `audio`
([PROTOCOL.md](PROTOCOL.md) §5). The sound itself is checked by ear on
the bench board's speaker ([DEVICE.md](DEVICE.md) §3):
`internal/tools/boopctl takes` plays every take, and
`internal/tools/boopctl play needs` plays needs you's alert
([VERIFICATION.md](VERIFICATION.md) §2).

## 9. How often Boop talks

When Boop reacts, and when it mustn't, is in [BEHAVIORS.md](BEHAVIORS.md)
§2, §4 and §6; whether it says something is the brain's and Voice's
(§4). On the device, a `state` with "needs you" or volume 0 stops a take
that's playing.

**When a take starts.** A take on its own plays at once, over whatever
face shows. A take that comes with an animation, as the brain's finish
sends one, starts at that design's voice window (§10), so it follows the
design's attention cue rather than talking over it; its sound, mouth and
bubble start together. The animation holds on, resting on its last
frame, until the take and its bubble end. A tap or "needs you" before
the window drops the take unplayed. The Mac reckons the same length for
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
