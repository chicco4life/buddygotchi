# Release Checklist

Use this as the ordered release gate for app and firmware releases.

1. Confirm the release tag and version:
   - App tags use `vX.Y.Z`.
   - Firmware tags use `fw-vX.Y.Z`.
2. Run local app checks using [TESTING.md section 1](TESTING.md#1-unit-tests).
3. Run snapshot/visual review using [TESTING.md section 3](TESTING.md#3-snapshot-and-visual-review).
4. Run hook smoke checks with the app running outside the sandbox using [TESTING.md section 2](TESTING.md#2-http-e2e).
5. Verify installed hooks on a clean macOS user profile:
   - Claude Code CLI and Claude Desktop.
   - Codex CLI and Codex desktop with `codex_hooks = true`.
   - Cursor desktop and the VS Code extension on the managed helper path.
6. Verify manual approval behavior for each agent:
   - Allow a command.
   - Deny a command.
   - Stop Boop and confirm hooks fail open.
7. Package the app through the release workflow and download the draft release artifacts.
8. On a clean Mac, verify the packaged app using [TESTING.md section 4](TESTING.md#4-packaged-app-smoke).
9. Verify packaged fonts and sounds using [TESTING.md section 6](TESTING.md#6-asset-deployment).
10. Generate the appcast:
   - Put the signed app download artifacts in a downloads directory.
   - Run `app/tools/make-appcast.sh <sparkle-bin-dir> <downloads-dir>`.
   - Open a Pages PR updating `/releases/appcast.xml`.
11. Build firmware through the firmware release workflow and download the draft artifacts.
12. Verify firmware OTA on a real M5StickC Plus 2 using [TESTING.md section 5](TESTING.md#5-firmware-update-ota).
13. Run hardware HIL using [TESTING.md section 7](TESTING.md#7-hardware-hil).
14. Publish firmware hosting:
    - Open a Pages PR for `/firmware/manifest.json`.
    - Open a Pages PR for `/firmware/esp-web-tools-manifest.json`.
    - Confirm the flash page installs without Home Assistant prompts using [TESTING.md section 8](TESTING.md#8-web-flasher).
15. Re-run hardware screenshots for attention, busy, review, error, thinking, and multi-session states after firmware wire-format changes using [TESTING.md section 7](TESTING.md#7-hardware-hil).
16. Publish the draft GitHub releases after appcast and firmware hosting are live.
17. Announce the release with links to the app download, appcast, firmware manifest, support page, and flash page.
