# A4: Device link, app shell, push-to-talk and installer

2026-09-26, iteration after A3 was blocked. Board untouched: still on F4
firmware `3707c8eb51`.

## What was built

| Part | Where |
| --- | --- |
| Device link: line framing, `status`/`input` decoding, `state` on change and every 10 s, `state` in reply to `status` and on connect, moments | `app/BoopKit/DeviceLink/DeviceLink.swift`, `DeviceMessage.swift` |
| USB transport: client of `boopctl bridge`'s socket, reconnects every second | `app/BoopKit/DeviceLink/USBTransport.swift` |
| Bluetooth central: scans for `Boop-*` with the NUS service, no pairing, writes in pieces of the link's size, reconnects with a backoff to 30 s | `app/BoopKit/DeviceLink/BLETransport.swift` (built; never run here) |
| The runtime: hooks → adapters → core → actions, harness, memory, device link; inputs back to the core; one queue | `app/BoopKit/App/Runtime.swift` |
| Settings (`settings.json`: brain, volume, focus, away, record), one-app-per-state-dir lock | `app/BoopKit/App/AppSettings.swift` |
| Installer: install, repair, remove for Claude and Codex; removes gen-2 `~/.boop/boop-hook.sh` entries; Codex feature switch | `app/BoopKit/Install/HookInstaller.swift` |
| `Boop --headless --state-dir --link --socket [--brain --name --nature --debug-log]` | `app/Boop/Headless.swift` |
| Menu bar: icon (outline idle, dot working, amber needs you), popover, settings, first-run setup | `app/Boop/MenuBarApp.swift`, `app/Boop/Views/` |
| Push-to-talk: Speech framework, on-device only, audio never kept | `app/Boop/Talk.swift` |
| API key in the Keychain; cloud brain shown as not available | `app/Boop/Keychain.swift` |
| `Info.plist` with the Bluetooth, microphone and speech usage descriptions, linked into the binary | `app/Boop/Info.plist`, `app/Package.swift` |
| Bundled `steering.md` (a test keeps it identical to `plan/steering.md`) | `app/Boop/Resources/steering.md` |
| `boopctl bridge`; other `boopctl` commands use a running bridge | `tools/boopctl_lib/bridge.py`, `device.py` |
| `boopdev talk`, `boopdev hooks` | `app/BoopDev/main.swift` |
| Doctor, rewritten for the socket | `skills/doctor/doctor.sh`, `SKILL.md` |

## Checks

| Check | Result | Evidence |
| --- | --- | --- |
| `make build` | Pass | [build.txt](build.txt) |
| L0 `make test` | **160/160 pass** (was 135): 9 device-link, 10 installer, 6 runtime tests added | [tests.txt](tests.txt) |
| Installer on a temporary HOME: idempotent (second install doesn't rewrite the file), keeps other hooks, removes old and current Boop entries only, leaves unreadable files alone | Pass (`InstallerTests`) | |
| Device-link encoding: framing across packets, overlong lines, Bluetooth chunks, `status`/`input` decoding, the `moment` line byte for byte, 10 s keepalive, reply to `status` | Pass (`DeviceLinkTests`) | |
| The app builds, headless mode starts and stops cleanly | Pass: SIGTERM → exit 0, hook socket and bridge socket removed; a second app on the same state directory is refused | [usb-live.txt](usb-live.txt), `RuntimeTests` |
| Live over USB: hooks → `boop-hook` → headless app → bridge → board | Pass: the board went from asleep to "needs you" (claude · jetpack, rung 1) on `PermissionRequest`, nodded on `Stop`; hold → `talk_on`/`talk_off`, tap → `input tap` reached the app; `boopdev talk "shut up"` → sulky + 30 min quiet shown on the board. The device's `status` got a `state` back (first run, 04:31:27) | [usb-live.txt](usb-live.txt), [usb-needs-you.png](usb-needs-you.png) |
| Doctor, headless, on a temporary HOME after `boopdev hooks install` | 7/7 pass | [doctor-temp-home.txt](doctor-temp-home.txt) |

Notes:

- `usb-live.txt`'s `settings.json` shows `"brain": "rules"`: the run's
  `--brain rules` override was being saved. Fixed after that run (overrides
  are for the run only) and covered by `RuntimeTests`.
- On the owner's own setup the doctor (read-only) reports that
  `~/.claude/settings.json` and `~/.codex/hooks.json` still hold only the
  gen-2 `~/.boop/boop-hook.sh` entries. The v1 app's setup or launch repair
  replaces them; nothing here touched those files.
- Hook latency in `usb-live.txt` (~72 ms per payload) is `boopdev replay`
  timing the whole `boop-hook` process launch, not the app. J1 measures
  hook-to-device latency properly.

## Not checked here (needs the owner)

- The menu-bar app itself and Bluetooth: an agent must not launch the app
  with Bluetooth. `make run` in the morning.
- Push-to-talk with the real mic and the permission prompts.
- The setup window, settings, the Keychain write.
