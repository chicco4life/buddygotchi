# 05 — Hooks & Integrations: Health, Repair, and Not Eating the User's Config

Goal: hook installation becomes a *managed* integration — the app can tell installed from corrupted from outdated, repairs silently, never destroys user data, and survives app relocation and rebuilds. Plus: authenticate the localhost API.

Current implementation: `app/Buddygotchi/Install/HookInstaller.swift`, the generated bash script (`~/.buddygotchi/buddygotchi-hook.sh`), and `app/BuddygotchiSignal/SignalCLI.swift` for Cursor.

## 1. Hook health model (the user's headline ask)

`isInstalled(agent:)` today answers one bit: "does any command containing `buddygotchi` appear in the config?" It cannot detect: script file deleted, script not executable, script content from an older app version, missing event coverage (an agent update or a user edit dropped `PermissionRequest`), Codex `codex_hooks` flag removed, Cursor hooks pointing at a `BuddygotchiSignal` binary that no longer exists (rebuild wiped `.build/`, app moved out of `/Applications`), or an unparseable config file.

### 1.1 The model

```swift
enum HookHealth: Equatable {
    case notInstalled
    case installed                    // fully verified against current expectations
    case outdated(installed: Int, current: Int)   // older hook schema/script version
    case corrupted(reason: String)    // partially present, unreadable, or broken pieces
}
```

### 1.2 Versioning

- Add `static let hookSchemaVersion = 3` (an integer bumped whenever the installed hook set, script content, or helper binary contract changes).
- The **script** carries it: first lines of `hookScriptContent` become
  `#!/bin/bash`
  `# buddygotchi-hook v3 — managed by Buddygotchi.app; edits are overwritten on repair`
- The **agent configs** carry it implicitly via expected-shape verification (don't rely on comments in JSON — Claude's settings.json must stay comment-free). Verification derives the installed version from the script header plus structural checks.

### 1.3 `verify(agent:) -> HookHealth`

Per agent, check all of:

**Common:** `~/.buddygotchi/buddygotchi-hook.sh` exists, is executable (posix perms include `0o100`), and its content hash equals the current template's hash (compare after normalizing the version line, or just compare full content — the template is deterministic). Mismatch with a parseable older version header → `.outdated`; missing/garbled → `.corrupted("hook script missing")`. Also verify `config.json` exists and parses (the script needs it for the port).

**Claude Code:** parse `~/.claude/settings.json`. Parse failure → `.corrupted("settings.json is not valid JSON")` (and never auto-write — §2). Then check every expected event (`SessionStart`, `UserPromptSubmit`, `Stop`, `StopFailure`, `SessionEnd`, `PostToolUse`, `Elicitation`, `ElicitationResult`, `PermissionRequest`, and the three `Notification` matchers) has exactly one Buddygotchi entry whose command equals the canonical string. Missing events → `.corrupted("missing hooks: …")`; duplicates → `.corrupted("duplicate hooks")` (repair dedupes).

**Codex:** same nested-hook check on `~/.codex/hooks.json` for its six events, plus `config.toml` contains an *active* `codex_hooks = true` in `[features]` (the current substring check matches commented-out lines — parse minimally: find the `[features]` section, scan its lines for `codex_hooks` ignoring `#`-prefixed).

**Cursor:** `~/.cursor/hooks.json` has all eight events pointing at the canonical helper path (§3), **and** that helper binary exists and is executable. A hooks.json referencing a dead path is the classic silent failure today.

### 1.4 Repair & auto-repair

- `repair(agent:)` = uninstall (surgical removal of our entries only) + install, both atomic (§2). Because verify/repair are idempotent, "Repair" replaces "Reinstall" in the UI (03 §5).
- **On every app launch** (`AppDelegate`, off the critical path — `Task` after startup): for each agent the user previously connected (track `installedAgents: [String]` in UserDefaults, set on successful install, cleared on explicit disconnect), run `verify`; on `.outdated` → repair silently and log to diagnostics; on `.corrupted` where the *cause is ours* (script missing, binary missing, our entries malformed) → repair silently; on `.corrupted` where the *user's file is broken* (unparseable JSON) → do **not** touch it; surface in Settings + the popover hint (03 §1) with the reason.
- This is what makes the app-update story work: bump `hookSchemaVersion`, ship the update, every user's hooks self-heal on next launch.

### 1.5 Surfacing

- Settings → Agents rows render `HookHealth` (03 §5): green "connected", amber "needs repair — <reason>" with a Repair button, quiet "not connected" with Connect.
- Diagnostics: every verify/repair outcome logs (`category: "hooks"`), included in bug-report exports.
- Add `HookInstallError` (thrown or returned) replacing silent `Bool` returns, so onboarding (01 §3.3) and settings can show *why* an install failed (`cantWriteScript(path)`, `configUnreadable(agent)`, `serializationFailed`…).

## 2. Never destroy user config (P0)

Two data-loss hazards in the current installer:

1. **Unparseable file → overwrite.** `installClaudeCode` does `if let parsed … settings = parsed` — a `settings.json` with a trailing comma (users hand-edit this file constantly) parses as nil, `settings` stays `[:]`, and the write replaces the user's entire Claude configuration with only Buddygotchi hooks. Same pattern in `installCursor`/`installCodex`. **Fix:** distinguish "file absent" (proceed with `[:]`) from "file present but unparseable" (abort with `.configUnreadable`, surface in UI, never write).
2. **Non-atomic writes.** `fm.createFile(atPath:contents:)` truncates-then-writes; a crash mid-write corrupts the file. Replace every config write (`settings.json`, `hooks.json`, `config.toml`, `config.json`, the hook script) with `try data.write(to: url, options: .atomic)`.

Additional safety:

- **Backup before first-ever modification** of each agent file: copy to `~/.buddygotchi/backups/<agent>-<filename>-<yyyyMMdd-HHmmss>` (keep last 3). Cheap insurance; mention it in the Settings row hover ("we keep a backup").
- **Preserve unknown keys** (already does — dictionaries are read-modify-write; keep it that way when refactoring to Codable: use `JSONSerialization` for these files on purpose, since typed models would drop unknown keys).
- JSON writing uses `.sortedKeys` (already) — keep, it minimizes diff churn in the user's dotfiles.

## 3. Stable helper path (Cursor's binary, and the script)

`signalCLIPath()` points Cursor's hooks at `Bundle.main.executableURL/../BuddygotchiSignal` — i.e. `.build/debug/` during development (wiped by `make clean`) or inside the `.app` (breaks when the app is moved, e.g. running once from `~/Downloads` then dragging to `/Applications`; also churns if the bundle layout changes across updates).

Fix — install managed copies under the state dir:

- `~/.buddygotchi/bin/buddygotchi-signal` — copied from the bundle on install *and* on every launch-time verify when the bundled binary's hash differs (that's the upgrade path). `chmod 0o755`. Cursor hooks reference this path only.
- Signing note (see 06): the copied binary keeps its Developer ID signature (copying preserves it); Gatekeeper doesn't assess plain executables spawned by other processes the way it does app bundles, but keep the binary signed and hardened anyway.
- The bash script already lives at a stable path (`~/.buddygotchi/buddygotchi-hook.sh`) — good; it becomes versioned per §1.2.
- Delete the `?? "buddygotchi-signal"` fallback (a bare name that resolves via PATH — never correct here); if the bundled binary can't be found, installation fails loudly with `HookInstallError`.

## 4. Hook-script and SignalCLI hardening

- **Timeout alignment** (04 §3.6): script `--max-time 300`; set installed hook `timeout` values to 310 for approval hooks (Claude/Codex), keep 5 s for plain events. SignalCLI's approval wait is 300 s — consistent.
- The script's config parsing (`grep -o '"port" *: *[0-9]*'`) is deliberately dependency-free — keep, but guard the empty-port case explicitly (`[ -z "$PORT" ] && exit 0`) so a missing config never produces `curl http://127.0.0.1:/…` noise in agent logs.
- SignalCLI's Cursor `stop → stop_working` mapping is vestigial (the server rewrites it to `celebrate`). Fix at the source — map `"stop": "celebrate"` — and keep the server-side rewrite for one release as compat for old installed binaries (it's keyed on `source == "cursor" && signal == "stop_working"`, harmless), then remove.
- Add `"pid"` to SignalCLI's `/hook/signal` posts (query param like the bash script) so Cursor sessions can get process watchers too — today only Claude/Codex sessions are reaped by process exit. Requires `HookServer` to read `pid` on `/hook/signal` and pass `hookPid` into `sessionStarted`. Note Cursor's helper is spawned per-event like the script, so the same walk-two-parents caveat (04 §3.5) applies.
- SignalCLI always prints `{"permission":"allow"}` for non-approval events — correct per Cursor's contract (non-blocking hooks must answer); leave, but add a comment marking it as Cursor protocol, not a decision.

## 5. Authenticate the localhost API

Anything on the machine — including **any web page in a browser** issuing `fetch("http://127.0.0.1:21321/hook/event", {method: "POST", mode: "no-cors", …})` — can currently inject fake events, spam approval prompts (each blocks a Hummingbird task for up to 300 s), or flip session state. Local-first is a trust pillar; lock the door:

- On first run, generate a 32-byte random token, store as `"token"` in `~/.buddygotchi/config.json` (file perms `0o600`; the state dir is already user-private).
- Hook script and SignalCLI read it from the same config they already parse and send `-H "X-Buddygotchi-Token: $TOKEN"`.
- `HookServer` middleware rejects requests with a missing/wrong token with 401 for `/hook/*` (leave `/healthz` open — it leaks nothing but liveness/state version; or gate it too, trivial either way).
- Browsers can still *send* no-cors POSTs but cannot set the custom header → blocked. Local processes reading the user's own config file are inside the threat boundary (same user account), which is the right line for this product.
- Bump `hookSchemaVersion` (the script content changes) → launch-time auto-repair rolls it out.

## 6. Verification matrix & e2e

- Extend `app/tools/e2e/lib.sh` to read the token from config so the smoke tests keep working post-§5.
- Add `app/tools/e2e/verify-hooks.sh`: asserts `verify` outcomes by mutating fixtures — delete the script → expect corrupted; truncate settings.json → expect corrupted + untouched on repair attempt; downgrade script header → expect outdated + auto-repaired content.
- Keep `research/product/PRODUCT.md` §12.1's surface matrix in mind: the same three config writes cover CLI + desktop app + IDE extensions per vendor. The health check therefore also covers those surfaces for free. Add the per-surface release-test checklist to `research/eng/TODOs.md` (Claude desktop, Codex desktop, VS Code extension smoke before each release).
- Unit tests: see 04 §4 (HookInstaller tests with injected home dir) — that refactor is a prerequisite for testing everything in this doc.

## Acceptance criteria

- `echo '{broken' > ~/.claude/settings.json` then Connect → visible error, file byte-identical afterward.
- Delete `~/.buddygotchi/buddygotchi-hook.sh`, relaunch app → script restored automatically, diagnostics show a repair entry, Settings row shows "connected".
- Bump `hookSchemaVersion` in a dev build, relaunch → script rewritten, Cursor binary re-copied, agent configs updated, all without user action.
- `curl -X POST http://127.0.0.1:21321/hook/event -d '{}'` without the token → 401; the installed hook script still works.
- Move the built app bundle to a different directory, relaunch, run a Cursor hook → still fires (helper path is `~/.buddygotchi/bin`).
- `swift test --filter HookInstallerTests` covers fresh/idempotent/corrupted/legacy/TOML cases.
