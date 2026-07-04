# Release Checklist

Use this as the ordered release gate for app and firmware releases.

1. Confirm the release tag and version:
   - App tags use `vX.Y.Z`.
   - Firmware tags use `fw-vX.Y.Z`.
2. Run local app checks:
   - `make build`
   - `make test` on a machine with XCTest, or verify CI ran the full XCTest suite.
   - Snapshot harness for core popover states.
3. Run hook smoke checks with the app running outside the sandbox:
   - `make e2e`
   - `app/tools/e2e/claude.sh`
   - `app/tools/e2e/codex.sh`
   - `app/tools/e2e/cursor.sh`
4. Verify installed hooks on a clean macOS user profile:
   - Claude Code CLI and Claude Desktop.
   - Codex CLI and Codex desktop with `codex_hooks = true`.
   - Cursor desktop and the VS Code extension on the managed helper path.
5. Verify manual approval behavior for each agent:
   - Allow a command.
   - Deny a command.
   - Stop Buddygotchi and confirm hooks fail open.
6. Package the app through the release workflow and download the draft release artifacts.
7. On a clean Mac, verify the packaged app:
   - Gatekeeper launch succeeds.
   - Launch at Login works from the packaged `.app`.
   - Settings shows one `v` prefix and the expected build number.
   - Check for Updates opens Sparkle against the hosted appcast.
8. Generate the appcast:
   - Put the signed app download artifacts in a downloads directory.
   - Run `app/tools/make-appcast.sh <sparkle-bin-dir> <downloads-dir>`.
   - Open a Pages PR updating `/releases/appcast.xml`.
9. Build firmware through the firmware release workflow and download the draft artifacts.
10. Verify firmware on a real M5StickC Plus 2:
    - Pair over BLE.
    - Run heartbeat, approve, deny, and unpair checks.
    - OTA the release binary.
    - Confirm `tools/buddyctl.py ping --json` reports `fw == manifest.version`.
11. Publish firmware hosting:
    - Open a Pages PR for `/firmware/manifest.json`.
    - Open a Pages PR for `/firmware/esp-web-tools-manifest.json`.
    - Confirm the flash page installs without Home Assistant prompts.
12. Re-run hardware screenshots for attention, busy, review, error, thinking, and multi-session states after firmware wire-format changes.
13. Publish the draft GitHub releases after appcast and firmware hosting are live.
14. Announce the release with links to the app download, appcast, firmware manifest, support page, and flash page.
