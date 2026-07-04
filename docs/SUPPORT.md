# Boop Help

Boop runs locally. Agent hooks POST activity to `127.0.0.1`, the app turns that into buddy state, and optional approval mode waits for your allow or deny choice before returning a decision to the agent hook.

## What The Hooks Do

- Claude Code, Cursor, and Codex hooks call Boop when sessions start, prompts submit, tools run, tools finish, and sessions stop.
- Hooks fail open. If Boop is not running, the agent keeps its native behavior.
- Local approval mode is opt-in. When it is off, Boop observes activity without deciding tool permissions.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| Nothing connects | Open Boop, then run `curl http://127.0.0.1:21321/healthz`. Reinstall hooks from Settings if the endpoint responds. |
| Port busy | Quit other Boop copies. The packaged app enforces a single instance, but development runs may still leave old processes around. |
| Notifications do not appear | Use the packaged `.app`, then allow notifications in macOS System Settings. Bare `swift run` builds have limited notification identity. |
| Launch at login needs approval | macOS may require approval in System Settings, Login Items. Settings shows this state after the packaged app requests registration. |
| Hardware buddy is not found | Pair from Settings, Displays. If the device is blank or running other firmware, use the web flasher first. |

## Updates And Privacy

Boop app updates use a static Sparkle appcast at `https://adoptaboop.com/releases/appcast.xml`. Firmware updates use a static firmware manifest at `https://adoptaboop.com/firmware/manifest.json`. No analytics, crash-reporting service, or device identifier is sent by Boop.

## Manual Uninstall

The preferred path is Settings, About, Remove Boop. To remove manually:

```sh
rm -rf ~/.boop
```

Then remove Boop hook entries from:

- `~/.claude/settings.json`
- `~/.cursor/hooks.json`
- `~/.codex/hooks.json`
- `~/.codex/config.toml` (`codex_hooks = true`, if Boop was the only hook user)

Contact: hello@adoptaboop.com
