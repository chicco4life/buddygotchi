# TODOs

## Testing

- [ ] Test Cursor `beforeMCPExecution` approval flow — verify tool name and hint show correctly, auto-approve works for safe MCP tools (Read, Glob, Grep)
- [ ] Test Cursor `sessionStart` / `sessionEnd` — buddy should go sleep → idle → sleep
- [ ] Test Cursor `beforeSubmitPrompt` → `afterShellExecution` — buddy should go idle → busy → busy (keep working)
- [ ] Test Cursor `stop` — buddy should go busy → idle
- [ ] Remove debug logging from `/hook/approve` in HookServer.swift after Cursor testing is complete

## Cursor Integration

- [ ] HookInstaller uses `signalCLIPath()` which resolves relative to `Bundle.main.executableURL` — verify this resolves correctly for both development (`swift run`) and packaged (.app) builds
- [ ] Test `beforeMCPExecution` payload shape — we added `toolName` field but haven't confirmed Cursor actually sends it (vs some other field name)

## Packaging

- [ ] Launch at Login (`SMAppService`) requires a proper .app bundle — currently fails silently during development via `swift run`
- [ ] Cursor hooks hardcode the binary path — need a stable install location so hooks survive rebuilds
