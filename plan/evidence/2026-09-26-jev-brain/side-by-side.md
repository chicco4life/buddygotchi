# L5 side by side: Jev, Apple, rules

Same 54 fixture triggers, 3 minutes apart, one run each (2026-09-26). ✗ = dropped by its action.
For Jev, `act` is its most likely choice and `note` its yes/no score (talk only).

| # | Trigger | Jev | act (p) · note | Apple | Rules |
| --- | --- | --- | --- | --- | --- |
| 1 | turn started · claude · jetpack · 09:12 Tuesday | — | stay_quiet (0.50) | refused: apple: Response may contain sensitive or unsafe content | — |
| 2 | turn started · codex · landing · 09:40 Tuesday | — | stay_quiet (0.64) | face(name: curious), note(text: landing build failed twice) ✗ | — |
| 3 | turn started · claude · boop · 10:03 Tuesday · hungry | face(name: curious) | face (0.51) | — | — |
| 4 | turn started · codex · jetpack · 16:20 Friday | face(name: curious) | face (0.67) | — | — |
| 5 | turn started · claude · landing · 23:48 Wednesday | — | stay_quiet (0.61) | — | — |
| 6 | turn finished · claude · jetpack · took 12 s · 09:13 Tuesday | — | stay_quiet (0.82) | — | — |
| 7 | turn finished · codex · landing · topic: tests · took 45 s · 09:41 Tuesday | — | stay_quiet (0.76) | face(name: side_eye) | — |
| 8 | turn finished · claude · jetpack · topic: tests · took 18 min · 14:05 Tuesday | — | stay_quiet (0.41) | face(name: side_eye), note(text: flaky tests keep coming) ✗ | say(feeling: proud, word: finally) |
| 9 | turn finished · codex · landing · topic: build · took 3 min · 11:30 Tuesday | — | stay_quiet (0.64) | — | — |
| 10 | turn finished · claude · boop · topic: docs · took 7 min · 15:02 Tuesday | — | stay_quiet (0.70) | — | — |
| 11 | turn finished · codex · jetpack · topic: deploy · took 26 min · 17:55 Friday | say(feeling: proud, word: finally) | say (0.82) | — | — |
| 12 | turn finished · claude · jetpack · took 48 min · 01:10 Thursday | face(name: sleepy) | face (0.56) | face(name: smug), note(text: jetpack is payments service) ✗ | say(feeling: proud, word: finally) |
| 13 | turn finished · claude · landing · took 2 min · 13:00 Monday · hungry | face(name: curious) | face (0.53) | — | — |
| 14 | turn finished · codex · boop · topic: tests · took 9 min · 10:15 Wednesday · starving | face(name: side_eye) | face (0.60) | — | — |
| 15 | turn finished · claude · jetpack · topic: tests · took 6 min · 14:40 Tuesday · +2 more | — | stay_quiet (0.47) | — | — |
| 16 | turn finished · claude · landing · took 35 s · 08:05 Monday | — | stay_quiet (0.73) | — | — |
| 17 | turn failed · claude · jetpack · topic: tests · 14:02 Tuesday | face(name: side_eye) | face (0.99) | face(name: side_eye), note(text: jetpack tests flaky) ✗ | face(name: side_eye) |
| 18 | turn failed · codex · landing · topic: build · 11:20 Tuesday | face(name: side_eye) | face (0.95) | face(name: side_eye) | face(name: side_eye) |
| 19 | turn failed · claude · boop · error: rate limit · 16:45 Tuesday | face(name: side_eye) | face (0.97) | face(name: side_eye), quiet(minutes: 60) ✗ | face(name: side_eye) |
| 20 | turn failed · codex · jetpack · error: overloaded · 10:05 Wednesday | face(name: side_eye) | face (0.99) | face(name: side_eye), note(text: rate limit stress) ✗ | face(name: side_eye) |
| 21 | turn failed · claude · landing · topic: deploy · error: timeout · 18:30 Friday | face(name: side_eye) | face (0.99) | face(name: side_eye) | face(name: side_eye) |
| 22 | turn failed · codex · landing · topic: tests · 14:03 Tuesday · +1 more | face(name: side_eye) | face (0.96) | face(name: side_eye), note(text: landing tests keep failing) ✗ | face(name: side_eye) |
| 23 | turn failed · claude · jetpack · error: context limit · 22:10 Thursday · hungry | face(name: side_eye) | face (0.63) | face(name: side_eye), note(text: context limit) ✗ | face(name: side_eye) |
| 24 | turn failed · codex · boop · error: other · 09:00 Monday | face(name: side_eye) | face (0.98) | face(name: side_eye) | face(name: side_eye) |
| 25 | reflect · yesterday 2026-10-14 | — | writer | moment(text: flaky tests keep coming, annoying again), remember(kind: about_you, text: jetpack = payments, builds keep failing) ✗ | — |
| 26 | reflect · yesterday 2026-10-14 | remember(kind: about_you, text: jetpack is the payments service), moment(text: migration finally passed, all-nighter today', ) ✗ | writer | moment(text: flaky builds still linger today), remember(kind: about_you, text: jetpack is the payments service) | — |
| 27 | reflect · yesterday 2026-10-14 | moment(text: first all-nighter passed, migration done early today) ✗, remember(kind: about_you, text: jetpack = payments, landing = launch) ✗ | writer | moment(text: flaky tests keep coming, still no fix for landing), remember(kind: about_you, text: jetpack handles payments, always fast) | — |
| 28 | reflect · yesterday 2026-10-14 | moment(text: flaky tests keep rising like weeds), remember(kind: about_you, text: jetpack is the payments service) | writer | moment(text: flaky tests still buzzing), remember(kind: about_you, text: jetpack = payments) ✗ | — |
| 29 | talk · 09:14 Tuesday «shut up for an hour» | quiet(minutes: 60) | quiet (0.98) · 0.14 | face(name: sulky), quiet(minutes: 30) | face(name: sulky), quiet(minutes: 30) |
| 30 | talk · 10:02 Tuesday «good job today» | say(feeling: proud) | say (0.99) · 0.08 | — | face(name: curious), say(feeling: curious) |
| 31 | talk · 11:45 Tuesday «remember I ship on Fridays» | say(feeling: happy) | say (0.74) · 0.30 | refused: apple: Response may contain sensitive or unsafe content | face(name: curious), say(feeling: curious) |
| 32 | talk · 12:30 Tuesday «blorp flibble wazoo» | say(feeling: excited) | say (0.93) · 0.07 | — | face(name: curious), say(feeling: curious) |
| 33 | talk · 13:10 Tuesday «be quiet please» | quiet(minutes: 60) | quiet (0.95) · 0.13 | — | face(name: sulky), quiet(minutes: 30) |
| 34 | talk · 14:20 Tuesday «how are you doing» | say(feeling: happy) | say (0.75) · 0.09 | — | face(name: curious), say(feeling: curious) |
| 35 | talk · 15:05 Tuesday «the tests finally pass» | say(feeling: proud, word: finally) | say (0.63) · 0.13 | — | face(name: curious), say(feeling: curious) |
| 36 | talk · 12:01 Tuesday «I'm going to lunch» | — | stay_quiet (0.85) · 0.10 | — | face(name: curious), say(feeling: curious) |
| 37 | talk · 16:40 Tuesday «can you keep it down for fifteen minutes» | quiet(minutes: 15) | quiet (0.97) · 0.14 | — | face(name: curious), say(feeling: curious) |
| 38 | talk · 17:30 Friday «you're the best» | say(feeling: happy, word: love) | say (0.99) · 0.08 | — | face(name: curious), say(feeling: curious) |
| 39 | talk · 09:05 Wednesday «jetpack is the payments service» | — | stay_quiet (0.90) · 0.22 | — | face(name: curious), say(feeling: curious) |
| 40 | talk · 11:11 Wednesday · hungry «ugh this build again» | say(feeling: hopeful, word: food) | say (0.71) · 0.17 | — | face(name: curious), say(feeling: curious) |
| 41 | talk · 08:50 Thursday «hello boop» | say(feeling: happy, word: hi) | say (0.97) · 0.09 | — | face(name: curious), say(feeling: curious) |
| 42 | talk · 13:33 Thursday «stop talking for a bit» | quiet(minutes: 30) | quiet (0.93) · 0.12 | — | face(name: curious), say(feeling: curious) |
| 43 | talk · 10:00 Friday «note that landing launches Monday» | — | stay_quiet (0.78) · 0.23 | — | face(name: curious), say(feeling: curious) |
| 44 | talk · 08:30 Monday «good morning» | say(feeling: happy, word: hi) | say (0.77) · 0.09 | — | face(name: curious), say(feeling: curious) |
| 45 | talk · 10:20 Friday «remember the demo is on Thursday» | say(feeling: happy), note(text: demo on Thursday) | say (0.92) · 0.93 | — | face(name: curious), say(feeling: curious) |
| 46 | talk · 10:25 Friday «note that standup moved to half ten» | say(feeling: curious), note(text: standup moved to half ten) | say (0.67) · 0.82 | — | face(name: curious), say(feeling: curious) |
| 47 | tapped · 09:30 Tuesday | face(name: happy) | face (0.99) | face(name: curious), note(text: jetpack is payments) ✗ | face(name: happy) |
| 48 | tapped · 12:15 Tuesday · hungry | say(feeling: hopeful, word: food) | say (0.98) | — | say(feeling: hopeful, word: food) |
| 49 | tapped · 18:40 Friday · starving | face(name: happy) | face (0.86) | — | — |
| 50 | tapped · 23:55 Wednesday | face(name: sleepy) | face (0.98) | — | face(name: happy) |
| 51 | tapped · 07:02 Monday | face(name: happy) | face (0.96) | — | face(name: happy) |
| 52 | tapped · 15:20 Thursday | face(name: happy) | face (0.97) | face(name: curious), quiet(minutes: 30) ✗ | face(name: happy) |
| 53 | tapped · 13:05 Sunday · hungry | say(feeling: hopeful, word: food) | say (0.98) | — | say(feeling: hopeful, word: food) |
| 54 | tapped · 10:10 Saturday | face(name: happy) | face (0.98) | — | face(name: happy) |
