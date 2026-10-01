# Boop headless over the USB link, on LinkKit

The Mac lane's live check of 2026-09-30 ([PLAN.md](../PLAN.md)): the whole
runtime, `Boop --headless`, over `--link usb:` to a fake device on a Unix
socket, as `boopctl bridge` would present the board. No board, no
Bluetooth. It proves the Mac's half only: the device's half is proven by
the firmware's own tests.

The fake device ([fakedev.py](fakedev.py)) answers as linkkit/device's kit
does over USB: the app counts as there while it has spoken in the last
30 s, across socket connections (the board can't see the app's socket
close), and the app's first line after that silence gets a `hello`, as
does the app's own `{"t":"hello"}` ask. Each `do` ends `done` 1.5 s
after it arrives.

[run.sh](run.sh) makes two launches on one state directory, the second
3 s after the first stops, so the fake device still counts the app as
there and says no `hello` unasked. Each forces a proud reaction (the
dashboard's `{"dev":"answer",…}`) and waits for its `ended`. From the repo
root, after `make build`:

```sh
sh plan/evidence/2026-09-30-link-kit/headless-usb/run.sh
```

## What it shows

- **Each launch asks for the `hello` first, then sends its `state`**
  ([boop.log](boop.log): `link rules → {"t":"hello"}`, then the `state`;
  [heard.jsonl](heard.jsonl), what the fake device heard on each
  connection). On the second launch the device answers only because it
  was asked. Without the ask (the lane's first version), a relaunch within
  30 s got no `hello` until the device's own, up to 60 s later, and every
  reaction meanwhile failed `the device hasn't said hello`.
- **The reaction goes out at once and ends as the device says**, on both
  launches: `link brain → {"t":"do",…}`, then `device: do N ended done`
  1.5 s later, and in `debug.jsonl` the forced pass, the `sent` `do`, the
  `did` started (`open`) and its `ended` `done`
  ([harness/DECISIONS.md](../../../harness/DECISIONS.md) §5 quotes the first
  launch's).
- The log lines the tools read are there: `device link: connected`,
  `link brain|rules → …`, `device: <id> firmware <fw>`, and
  `device: do N ended HOW`.

| File | What |
| --- | --- |
| [boop.log](boop.log) | Both launches' app log |
| [debug.1.jsonl](debug.1.jsonl), [debug.jsonl](debug.jsonl) | The first and the second launch's `debug.jsonl` |
| [heard.jsonl](heard.jsonl) | Every line the fake device heard, with its connection's number |
| [fakedev.py](fakedev.py), [run.sh](run.sh) | The fake device and the run |
