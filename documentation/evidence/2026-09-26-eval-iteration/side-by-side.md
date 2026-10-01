# L5 side by side: the if-else classifier and Jev, both writing with Apple's model

The 58 fixture inputs, 3 minutes apart, one run each (2026-09-26), at the end of the eval iteration ([README](README.md)). A mumble is its feeling and word; ✗ = dropped by its action.

| # | Input | if-else + Apple | Jev + Apple |
| --- | --- | --- | --- |
| 1 | agent started · claude · jetpack · 09:12 Tuesday | — | — |
| 2 | agent started · codex · landing · 09:40 Tuesday | — | — |
| 3 | agent started · claude · boop · 10:03 Tuesday | — | — |
| 4 | agent started · codex · jetpack · 16:20 Friday | — | — |
| 5 | agent started · claude · landing · 23:48 Wednesday | — | — |
| 6 | agent finished · done · claude · jetpack · a short turn (12 s) · 09:13 Tuesday | — | — |
| 7 | agent finished · done · codex · landing · topic: tests · a long turn (45 s) · 09:41 Tuesday | proud “done” | proud “finally” |
| 8 | agent finished · done · claude · jetpack · topic: tests · a very long turn (18 min) · 14:05 Tuesday | proud “finally” | proud “finally” |
| 9 | agent finished · done · codex · landing · topic: build · a very long turn (3 min) · 11:30 Tuesday | proud “done” | proud “done” |
| 10 | agent finished · done · claude · boop · topic: docs · a very long turn (7 min) · 15:02 Tuesday | proud “finally” | proud “finally” |
| 11 | agent finished · done · codex · jetpack · topic: deploy · a very long turn (26 min) · 17:55 Friday | proud “finally” | proud “done” |
| 12 | agent finished · done · claude · jetpack · a very long turn (48 min) · 01:10 Thursday | proud “finally” | proud “finally” |
| 13 | agent finished · done · claude · landing · a very long turn (2 min) · 13:00 Monday | proud “finally” | proud “finally” |
| 14 | agent finished · done · codex · boop · topic: tests · a very long turn (9 min) · 10:15 Wednesday | proud “finally” | proud “finally” |
| 15 | agent finished · done · claude · jetpack · topic: tests · a very long turn (6 min) · 14:40 Tuesday · +2 more | proud “finally” | proud “finally” |
| 16 | agent finished · done · claude · landing · a long turn (35 s) · 08:05 Monday | proud “done” | proud “done” |
| 17 | agent finished · failed · claude · jetpack · topic: tests · 14:02 Tuesday | annoyed “ugh” | annoyed “tests” |
| 18 | agent finished · failed · codex · landing · topic: build · 11:20 Tuesday | annoyed “build” | annoyed “build” |
| 19 | agent finished · failed · claude · boop · error: rate limit · 16:45 Tuesday | annoyed “ugh” | annoyed “ugh” |
| 20 | agent finished · failed · codex · jetpack · error: overloaded · 10:05 Wednesday | annoyed “bug” | annoyed “bug” |
| 21 | agent finished · failed · claude · landing · topic: deploy · error: timeout · 18:30 Friday | annoyed “deploy” | annoyed “deploy” |
| 22 | agent finished · failed · codex · landing · topic: tests · 14:03 Tuesday · +1 more | annoyed “tests” | annoyed “tests” |
| 23 | agent finished · failed · claude · jetpack · error: context limit · 22:10 Thursday | annoyed “ugh” | annoyed “ugh” |
| 24 | agent finished · failed · codex · boop · error: other · 09:00 Monday | annoyed “ugh” | annoyed “ugh” |
| 25 | new day · yesterday 2026-10-14 | — | — |
| 26 | new day · yesterday 2026-10-14 | — | — |
| 27 | new day · yesterday 2026-10-14 | — | — |
| 28 | new day · yesterday 2026-10-14 | — | — |
| 29 | poked again and again · 09:31 Tuesday | annoyed “nope” | annoyed “nope” |
| 30 | poked again and again · 12:16 Tuesday | annoyed “nope” | annoyed “nope” |
| 31 | poked again and again · 23:56 Wednesday | annoyed “nope” | annoyed “nope” |
| 32 | poked again and again · 15:21 Thursday | annoyed “nope” | annoyed “nope” |
| 33 | you said · 09:14 Tuesday "shut up for an hour" | sad “oh” | sad “oh” |
| 34 | you said · 10:02 Tuesday "good job today" | proud “thanks” | happy “love” |
| 35 | you said · 11:45 Tuesday "remember I ship on Fridays" | happy “ship”, note "remember I ship on Fridays" | happy “ship” |
| 36 | you said · 12:30 Tuesday "blorp flibble wazoo" | curious “whee” | excited “whee” |
| 37 | you said · 13:10 Tuesday "be quiet please" | quiet(minutes: 30) | quiet(minutes: 30) |
| 38 | you said · 14:20 Tuesday "how are you doing" | curious “hi” | happy “hi” |
| 39 | you said · 15:05 Tuesday "the tests finally pass" | curious “hmm” | proud “finally” |
| 40 | you said · 12:01 Tuesday "I'm going to lunch" | hopeful “bye” | hopeful “bye” |
| 41 | you said · 16:40 Tuesday "can you keep it down for fifteen minutes" | sad “oh” | — |
| 42 | you said · 17:30 Friday "you're the best" | proud “love” | happy “love” |
| 43 | you said · 09:05 Wednesday "jetpack is the payments service" | curious “food” | note "jetpack is the payments service" ✗ |
| 44 | you said · 11:11 Wednesday "ugh this build again" | curious “ugh” | annoyed “ugh” |
| 45 | you said · 08:50 Thursday "hello boop" | happy “hi” | happy “hi” |
| 46 | you said · 13:33 Thursday "stop talking for a bit" | sad “oh” | — |
| 47 | you said · 10:00 Friday "note that landing launches Monday" | happy “hi”, note "landing launches Monday" ✗ | note "landing launches Monday" ✗ |
| 48 | you said · 08:30 Monday "good morning" | happy “hi” | happy “hi” |
| 49 | you said · 10:20 Friday "remember the demo is on Thursday" | happy “okay”, note "demo on Thursday" | happy “okay”, note "demo on Thursday" |
| 50 | you said · 10:25 Friday "note that standup moved to half ten" | happy “hi”, note "standup moved to half ten" | note "standup moved to half ten" |
| 51 | you said · 09:20 Tuesday "what's up" | curious “hi” | happy “hi” |
| 52 | you said · 12:40 Wednesday "time for lunch" | hopeful “food” | hopeful “food” |
| 53 | you said · 16:10 Thursday "that was a long one" | curious “yay” | proud “finally” |
| 54 | you said · 18:05 Friday "see you tomorrow" | happy “bye” | happy “bye” |
| 55 | you said · 16:10 Tuesday "you're so annoying" | sad “oh” | sad “oh” |
| 56 | you said · yelled · 16:05 Tuesday "what are you doing" | sad “oh” | sad “oh” |
| 57 | you said · yelled · 16:12 Tuesday "" | sad “oh” | sad “oh” |
| 58 | you said · 14:45 Monday "be quiet for half an hour" | quiet(minutes: 30) | quiet(minutes: 30) |
