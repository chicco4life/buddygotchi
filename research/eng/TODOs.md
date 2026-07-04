# TODOs

Last updated: 2026-07-03

## Production

- [ ] Package, sign, and notarize the macOS app.
- [ ] Verify Launch at Login from a packaged `.app`.
- [ ] Install hook helper binaries into a stable path outside `.build`.
- [ ] Exercise hook install/uninstall on a clean macOS user profile.
- [ ] Add release notes and versioning for app builds.

## Agent Integrations

- [ ] Use `research/eng/RELEASE.md` for the per-release agent smoke matrix.

## ESP32

- [ ] Host the firmware `manifest.json` and release `.bin` files.
- [ ] Run OTA update through BLE against a real device.
- [ ] Re-run hardware screenshots for attention, busy, review, error, thinking, and multi-session states.

## Repo

- [ ] Decide whether to enforce `swift-format` in CI once the toolchain is pinned.
- [ ] Add a release workflow after signing/notarization decisions are settled.
