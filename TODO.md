# TODO

Owner-only items. Everything else in the plan is done or tracked in
`plan/PLAN.md`.

## Release (needs Apple credentials)

- [ ] Join the Apple Developer Program; install a Developer ID Application
      certificate; export `DEVELOPER_ID_APPLICATION` so `app/tools/package.sh`
      signs. Confirm with `security find-identity -v -p codesigning`.
- [ ] Notarization: `xcrun notarytool store-credentials` and set
      `NOTARYTOOL_PROFILE` (or `APPLE_ID`, `APPLE_TEAM_ID`,
      `APPLE_APP_SPECIFIC_PASSWORD`).
- [ ] Sparkle: download 2.6.4 (SHA in `app/tools/release-preflight.sh`), set
      `SPARKLE_FRAMEWORK_PATH`; generate EdDSA keys with Sparkle's
      `generate_keys`, keep the private key, set `SPARKLE_PUBLIC_ED_KEY`.
- [ ] App icon: nothing exists; `AppIcon.icns` goes in `app/Boop/Resources/`.
      Brand is still undecided (`plan/VISION.md`).
- [ ] `make preflight` (signed mode) green, then tag and let
      `.github/workflows/release.yml` build; publish the appcast.
- [ ] Firmware: tag `fw-v*` so `.github/workflows/firmware-release.yml` builds
      the manifest; host it at the firmware manifest URL.
- [ ] Optional: `brew install create-dmg` for a DMG instead of the zip.

## Doctor from the other harnesses

- [ ] From a Codex CLI session in this repo: `skills/doctor/doctor.sh`, then
      `echo BOOP_DOCTOR_PING` as a tool call, then `--confirm`. Record the
      result in `app/Tests/Fixtures/hooks/VERSIONS.md`.
- [ ] Same from a Cursor chat (Cursor is not installed on the build Mac).
- [ ] Record Cursor hook fixtures with `app/tools/record-hooks.sh cursor`.

## Hardware (needs ears and hours)

- [ ] Overnight battery run on the buddy, unplugged; note hours to shutdown.
- [ ] Listen to the six motifs on the speaker board; tune in
      `firmware/esp32/firmware/sound` per `plan/UX-DEVICE.md`.
- [ ] Voice bench on another Mac (macOS 26 FoundationModels vs. fallback).
