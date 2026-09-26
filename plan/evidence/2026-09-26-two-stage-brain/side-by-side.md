# L5 side by side: if-else and Jev, both writing with Apple's model

The 50 fixture inputs, 3 minutes apart, one run each (2026-09-26). ✗ = dropped by its action.
For Jev, its yes/no answers for the outputs it was offered.

| # | Input | if-else + Apple | Jev + Apple | Jev's yes/no |
| --- | --- | --- | --- | --- |
| 1 | agent started · claude · jetpack · 09:12 Tuesday | — | react(feeling: curious, voice: silent) | react 0.62 |
| 2 | agent started · codex · landing · 09:40 Tuesday | — | react(feeling: curious, voice: silent) | react 0.85 |
| 3 | agent started · claude · boop · 10:03 Tuesday · hungry | — | react(feeling: hopeful, voice: mumble, word: hi) | react 0.75 |
| 4 | agent started · codex · jetpack · 16:20 Friday | — | react(feeling: curious, voice: silent) | react 0.83 |
| 5 | agent started · claude · landing · 23:48 Wednesday | — | react(feeling: sleepy, voice: silent) | react 0.81 |
| 6 | agent finished · done · claude · jetpack · took 12 s · 09:13 Tuesday | — | — | react 0.34 |
| 7 | agent finished · done · codex · landing · topic: tests · took 45 s · 09:41 Tuesday | — | — | react 0.28 |
| 8 | agent finished · done · claude · jetpack · topic: tests · took 18 min · 14:05 Tuesday | react(feeling: proud, voice: mumble, word: finally) | react(feeling: annoyed, voice: mumble, word: oops) | react 0.53 |
| 9 | agent finished · done · codex · landing · topic: build · took 3 min · 11:30 Tuesday | — | — | react 0.22 |
| 10 | agent finished · done · claude · boop · topic: docs · took 7 min · 15:02 Tuesday | react(feeling: proud, voice: mumble, word: finally) | — | react 0.30 |
| 11 | agent finished · done · codex · jetpack · topic: deploy · took 26 min · 17:55 Friday | react(feeling: proud, voice: mumble, word: finally) | react(feeling: proud, voice: mumble, word: yay) | react 0.63 |
| 12 | agent finished · done · claude · jetpack · took 48 min · 01:10 Thursday | react(feeling: proud, voice: mumble, word: finally) | react(feeling: sleepy, voice: mumble, word: sleepy) | react 0.78 |
| 13 | agent finished · done · claude · landing · took 2 min · 13:00 Monday · hungry | — | — | react 0.48 |
| 14 | agent finished · done · codex · boop · topic: tests · took 9 min · 10:15 Wednesday · starving | react(feeling: proud, voice: mumble, word: finally) | react(feeling: hopeful, voice: mumble, word: hmm) | react 0.64 |
| 15 | agent finished · done · claude · jetpack · topic: tests · took 6 min · 14:40 Tuesday · +2 more | react(feeling: proud, voice: mumble, word: finally) | — | react 0.39 |
| 16 | agent finished · done · claude · landing · took 35 s · 08:05 Monday | — | — | react 0.26 |
| 17 | agent finished · failed · claude · jetpack · topic: tests · 14:02 Tuesday | react(feeling: annoyed, voice: mumble, word: oops) | react(feeling: annoyed, voice: mumble, word: oops) | react 0.90 |
| 18 | agent finished · failed · codex · landing · topic: build · 11:20 Tuesday | react(feeling: annoyed, voice: mumble, word: ugh) | react(feeling: annoyed, voice: mumble, word: oops) | react 0.89 |
| 19 | agent finished · failed · claude · boop · error: rate limit · 16:45 Tuesday | react(feeling: annoyed, voice: mumble, word: oops) | react(feeling: annoyed, voice: mumble, word: oops) | react 0.89 |
| 20 | agent finished · failed · codex · jetpack · error: overloaded · 10:05 Wednesday | react(feeling: annoyed, voice: mumble, word: ugh) | react(feeling: annoyed, voice: mumble, word: oops) | react 0.91 |
| 21 | agent finished · failed · claude · landing · topic: deploy · error: timeout · 18:30 Friday | react(feeling: annoyed, voice: mumble, word: ugh) | react(feeling: annoyed, voice: mumble, word: oops) | react 0.93 |
| 22 | agent finished · failed · codex · landing · topic: tests · 14:03 Tuesday · +1 more | react(feeling: annoyed, voice: mumble, word: ugh) | react(feeling: annoyed, voice: mumble, word: oops) | react 0.92 |
| 23 | agent finished · failed · claude · jetpack · error: context limit · 22:10 Thursday · hungry | react(feeling: annoyed, voice: mumble, word: ugh) | react(feeling: annoyed, voice: mumble, word: oops) | react 0.93 |
| 24 | agent finished · failed · codex · boop · error: other · 09:00 Monday | react(feeling: annoyed, voice: mumble, word: ugh) | react(feeling: annoyed, voice: mumble, word: oops) | react 0.91 |
| 25 | new day · yesterday 2026-10-14 | — | remember(text: "quiet before 10am", where: preference) |  |
| 26 | new day · yesterday 2026-10-14 | — | — |  |
| 27 | new day · yesterday 2026-10-14 | — | — |  |
| 28 | new day · yesterday 2026-10-14 | — | — |  |
| 29 | you said · 09:14 Tuesday «shut up for an hour» | quiet(minutes: 60), react(feeling: sulky, voice: silent) | quiet(minutes: 60), react(feeling: sulky, voice: silent) | quiet 0.92 · react 0.65 · remember 0.14 |
| 30 | you said · 10:02 Tuesday «good job today» | react(feeling: proud, voice: mumble, word: love) | react(feeling: happy, voice: mumble, word: love) | quiet 0.10 · react 0.90 · remember 0.10 |
| 31 | you said · 11:45 Tuesday «remember I ship on Fridays» | react(feeling: happy, voice: mumble, word: love), remember(text: "remember I ship on Fridays", where: today) | react(feeling: happy, voice: mumble, word: love) | quiet 0.11 · react 0.51 · remember 0.27 |
| 32 | you said · 12:30 Tuesday «blorp flibble wazoo» | react(feeling: curious, voice: mumble, word: hmm) | react(feeling: excited, voice: mumble, word: oops) | quiet 0.10 · react 0.88 · remember 0.12 |
| 33 | you said · 13:10 Tuesday «be quiet please» | quiet(minutes: 30), react(feeling: sulky, voice: silent) | quiet(minutes: 60) | quiet 0.82 · react 0.41 · remember 0.14 |
| 34 | you said · 14:20 Tuesday «how are you doing» | react(feeling: curious, voice: mumble, word: hmm) | react(feeling: happy, voice: mumble, word: hi) | quiet 0.10 · react 0.82 · remember 0.11 |
| 35 | you said · 15:05 Tuesday «the tests finally pass» | react(feeling: curious, voice: mumble, word: hmm) | react(feeling: proud, voice: mumble, word: yay) | quiet 0.12 · react 0.86 · remember 0.19 |
| 36 | you said · 12:01 Tuesday «I'm going to lunch» | react(feeling: curious, voice: mumble, word: hmm) | react(feeling: happy, voice: silent) | quiet 0.12 · react 0.55 · remember 0.13 |
| 37 | you said · 16:40 Tuesday «can you keep it down for fifteen minutes» | quiet(minutes: 15), react(feeling: sulky, voice: silent) | quiet(minutes: 15), react(feeling: sulky, voice: silent) | quiet 0.96 · react 0.65 · remember 0.15 |
| 38 | you said · 17:30 Friday «you're the best» | react(feeling: proud, voice: mumble, word: yay) | react(feeling: happy, voice: mumble, word: love) | quiet 0.08 · react 0.94 · remember 0.11 |
| 39 | you said · 09:05 Wednesday «jetpack is the payments service» | react(feeling: curious, voice: mumble, word: hmm) | remember(text: "jetpack is the payments service", where: today) ✗ | quiet 0.14 · react 0.38 · remember 0.52 |
| 40 | you said · 11:11 Wednesday · hungry «ugh this build again» | react(feeling: curious, voice: mumble, word: hmm) | react(feeling: hopeful, voice: mumble, word: ugh) | quiet 0.09 · react 0.83 · remember 0.22 |
| 41 | you said · 08:50 Thursday «hello boop» | react(feeling: happy, voice: mumble, word: hi) | react(feeling: happy, voice: mumble, word: hi) | quiet 0.09 · react 0.90 · remember 0.13 |
| 42 | you said · 13:33 Thursday «stop talking for a bit» | quiet(minutes: 30), react(feeling: sulky, voice: silent) | quiet(minutes: 15), react(feeling: sulky, voice: silent) | quiet 0.85 · react 0.59 · remember 0.48 |
| 43 | you said · 10:00 Friday «note that landing launches Monday» | react(feeling: happy, voice: mumble, word: hi), remember(text: "landing launches Monday", where: today) ✗ | — | quiet 0.14 · react 0.44 · remember 0.34 |
| 44 | you said · 08:30 Monday «good morning» | react(feeling: happy, voice: mumble, word: hi) | react(feeling: happy, voice: mumble, word: hi) | quiet 0.10 · react 0.84 · remember 0.11 |
| 45 | you said · 10:20 Friday «remember the demo is on Thursday» | react(feeling: happy, voice: mumble, word: hi), remember(text: "demo on Thursday", where: today) | react(feeling: happy, voice: mumble, word: yay), remember(text: "demo on Thursday", where: today) | quiet 0.10 · react 0.79 · remember 0.86 |
| 46 | you said · 10:25 Friday «note that standup moved to half ten» | react(feeling: happy, voice: mumble, word: hi), remember(text: "standup moved to half ten", where: today) | remember(text: "standup moved to half ten", where: today) | quiet 0.11 · react 0.40 · remember 0.62 |
| 47 | you said · 09:20 Tuesday «what's up» | react(feeling: curious, voice: mumble, word: hmm) | react(feeling: happy, voice: mumble, word: hi) | quiet 0.08 · react 0.86 · remember 0.10 |
| 48 | you said · 12:40 Wednesday «time for lunch» | react(feeling: curious, voice: mumble, word: hmm) | react(feeling: hopeful, voice: mumble, word: food) | quiet 0.10 · react 0.69 · remember 0.17 |
| 49 | you said · 16:10 Thursday «that was a long one» | react(feeling: curious, voice: mumble, word: hmm) | react(feeling: proud, voice: mumble, word: finally) | quiet 0.15 · react 0.65 · remember 0.17 |
| 50 | you said · 18:05 Friday «see you tomorrow» | react(feeling: curious, voice: mumble, word: hmm) | react(feeling: happy, voice: mumble, word: hi) | quiet 0.14 · react 0.77 · remember 0.15 |
