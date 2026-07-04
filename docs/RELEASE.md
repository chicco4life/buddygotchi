# Release Checklist

## App

1. Update `VERSION` and `CHANGELOG.md`.
2. Run `make test` and `make package` locally.
3. Tag `vX.Y.Z`.
4. Let `.github/workflows/release.yml` create a draft GitHub Release.
5. Download the artifact on a clean Mac and verify Gatekeeper launch, onboarding, notifications, launch at login, and Bluetooth pairing prompt timing.
6. Generate the Sparkle appcast with the private EdDSA key.
7. Open a Pages PR for `https://adoptaboop.com/releases/appcast.xml`; merge only after the clean-Mac check passes.

Required release secrets:

- `DEVELOPER_ID_CERTIFICATE_P12`
- `DEVELOPER_ID_CERTIFICATE_PASSWORD`
- `BUILD_KEYCHAIN_PASSWORD`
- `DEVELOPER_ID_APPLICATION`
- `NOTARYTOOL_PROFILE`
- `SPARKLE_PUBLIC_ED_KEY`

Optional release variables:

- `SPARKLE_FRAMEWORK_PATH`

## Firmware

1. Tag `fw-vX.Y.Z`.
2. Let `.github/workflows/firmware-release.yml` build firmware and draft a GitHub Release.
3. OTA the generated binary onto a real M5StickC Plus 2 from the app.
4. Flash a bare device from `docs/flash/index.html` served through GitHub Pages.
5. Open a Pages PR publishing `https://adoptaboop.com/firmware/manifest.json`, `https://adoptaboop.com/firmware/esp-web-tools-manifest.json`, and the versioned `.bin` files.

Rollback path: keep old binaries hosted and repoint `https://adoptaboop.com/firmware/manifest.json` to the last known good version.
