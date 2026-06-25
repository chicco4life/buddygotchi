# macOS Release Process

Buddygotchi ships outside the Mac App Store as a signed and notarized DMG hosted on GitHub Releases. The release pipeline keeps SwiftPM as the source of truth and assembles a conventional `Buddygotchi.app` bundle during release.

## Technologies

- **Developer ID Application certificate** signs the app for direct distribution. It is not an App Store certificate; it tells Gatekeeper that the app came from the company Apple Developer account.
- **Hardened Runtime** is enabled during signing. Apple expects this for notarized Mac software, and it limits runtime tampering.
- **Notarization** submits the signed DMG to Apple for malware and signing checks. This is still required for a smooth outside-App-Store install experience.
- **Stapling** attaches Apple's notarization ticket to the DMG so Gatekeeper can validate the download without immediately contacting Apple.
- **Sparkle 2** provides in-app updates. Buddygotchi checks an appcast XML feed, verifies the EdDSA signature, downloads the new DMG, and installs the update.
- **GitHub Releases** hosts the public DMG and `appcast.xml` feed.
- **GitHub Actions** builds, signs, notarizes, generates the appcast, and publishes releases from `v*` tags.

## One-Time Setup

1. Install full Xcode locally and in CI runners. Command Line Tools alone are not enough for reliable release builds.
2. Create a company **Developer ID Application** certificate in the Apple Developer account.
3. Export the certificate and private key from Keychain Access as a password-protected `.p12`.
4. Create an App Store Connect API key with notarization access and download its `.p8` key.
5. Generate a Sparkle EdDSA key pair with Sparkle's `generate_keys` tool.
6. Add `app/Buddygotchi/Resources/AppIcon.icns` before the first public release.
7. Add these GitHub repository secrets:
   - `APPLE_DEVELOPER_ID_APPLICATION_CERT_BASE64`
   - `APPLE_DEVELOPER_ID_APPLICATION_CERT_PASSWORD`
   - `APPLE_NOTARY_KEY_ID`
   - `APPLE_NOTARY_ISSUER_ID`
   - `APPLE_NOTARY_KEY_P8_BASE64`
   - `SPARKLE_PRIVATE_KEY_BASE64`
8. Add this GitHub repository variable:
   - `SPARKLE_PUBLIC_ED_KEY`

Encode files for GitHub secrets on macOS:

```bash
base64 -i DeveloperIDApplication.p12 | pbcopy
base64 -i AuthKey_ABC123DEFG.p8 | pbcopy
base64 -i sparkle_ed25519 | pbcopy
```

## Local Build

Create an unsigned/ad-hoc bundle for inspection:

```bash
scripts/release/build-app.sh 0.4.0 1
codesign --force --deep --sign - dist/Buddygotchi.app
codesign --verify --deep --strict --verbose=4 dist/Buddygotchi.app
```

For a signed local release build, set:

```bash
export APPLE_DEVELOPER_IDENTITY="Developer ID Application: Company Name (TEAMID)"
export SPARKLE_PUBLIC_ED_KEY="public-key-from-generate_keys"
scripts/release/build-app.sh 0.4.0 1
scripts/release/sign-app.sh
scripts/release/make-dmg.sh 0.4.0
```

Notarization requires either `APPLE_NOTARY_KEYCHAIN_PROFILE` or:

```bash
export APPLE_NOTARY_KEY_ID="ABC123DEFG"
export APPLE_NOTARY_ISSUER_ID="00000000-0000-0000-0000-000000000000"
export APPLE_NOTARY_KEY_PATH="/path/to/AuthKey_ABC123DEFG.p8"
scripts/release/notarize.sh dist/Buddygotchi-0.4.0.dmg
```

## Automated Release

1. Merge release-ready changes to `main`.
2. Create and push a tag:

```bash
git tag v0.4.0
git push origin v0.4.0
```

3. GitHub Actions runs `.github/workflows/release-macos.yml`.
4. The workflow uploads:
   - `Buddygotchi-0.4.0.dmg`
   - `appcast.xml`
   - `checksums.txt`

Sparkle reads the latest appcast from:

```text
https://github.com/chicco4life/buddygotchi/releases/latest/download/appcast.xml
```

## Verification Checklist

- `swift test` passes.
- `scripts/release/build-app.sh` produces `dist/Buddygotchi.app`.
- `lipo -info` reports both `arm64` and `x86_64` for the app and helper binaries.
- `codesign --verify --deep --strict --verbose=4 dist/Buddygotchi.app` passes.
- `xcrun stapler validate dist/Buddygotchi-VERSION.dmg` passes after notarization.
- The DMG mounts and the copied app launches from `/Applications`.
- Launch at Login works from the packaged app.
- Agent hook installs point to `~/.buddygotchi/bin`.
- Sparkle finds and installs a newer signed/notarized release.
