---
name: release
description: Cut a signed, notarized Buddygotchi release — preflight checks, package, verify, appcast, tag; use when the user wants to build/ship/release the Mac app.
---

# Buddygotchi Release

Use this when the user says "/release", "cut a release", or otherwise asks to build, ship, or publish the Mac app.

## Operating Procedure

1. Start at the repo root and run:

   ```sh
   make preflight
   ```

2. Relay the checklist results. If any `❌ HARD` item appears, stop before packaging or tagging. Tell the user exactly which requirement is missing:
   - Apple Developer Program membership and an installed Developer ID Application certificate.
   - `DEVELOPER_ID_APPLICATION` set to the exact identity from `security find-identity -v -p codesigning`.
   - Notarization credentials: either `NOTARYTOOL_PROFILE` from `xcrun notarytool store-credentials`, or the `APPLE_ID`, `APPLE_TEAM_ID`, and `APPLE_APP_SPECIFIC_PASSWORD` trio.
   - A valid semver `VERSION`, clean git tree, `main` checked out, and no existing `v$(cat VERSION)` tag.
   - Sparkle readiness warnings: `SPARKLE_FRAMEWORK_PATH`, `SPARKLE_PUBLIC_ED_KEY`, and hosting from `docs/RELEASE.md` or `research/eng/RELEASE.md`.

3. Never fabricate or guess credentials, signing identities, Sparkle keys, app-specific passwords, team IDs, or hosting state. Degrade to unsigned development builds only when the user explicitly asks for that.

## Preferred Release Path: CI

1. Confirm `make preflight` has no hard failures.
2. Confirm `VERSION` is the intended production version.
3. Tag and push the release commit:

   ```sh
   VERSION="$(tr -d '[:space:]' < VERSION)"
   git tag "v$VERSION"
   git push origin "v$VERSION"
   ```

4. The `.github/workflows/release.yml` tag workflow packages the app. It uses:
   - `DEVELOPER_ID_APPLICATION`
   - `NOTARYTOOL_PROFILE`
   - `APPLE_ID`
   - `APPLE_TEAM_ID`
   - `APPLE_APP_SPECIFIC_PASSWORD`
   - `SPARKLE_PUBLIC_ED_KEY`
   - `SPARKLE_FRAMEWORK_PATH` when provided, otherwise the workflow downloads pinned Sparkle `2.6.4`.
   - `BUDDY_VERSION` and `BUDDY_BUILD_NUMBER` inside CI.

5. Watch the workflow and inspect the draft GitHub release. The workflow summary includes the manual appcast gate:
   - Download the signed artifacts on a clean Mac and verify Gatekeeper launch.
   - Run `app/tools/make-appcast.sh "$SPARKLE_BIN_DIR" <downloads-dir>` with the Sparkle private EdDSA key available.
   - Open a Pages PR updating `/releases/appcast.xml`.

## Local Release Path

Use this only on a release-capable Mac with credentials present.

1. Export the same environment variables consumed by `app/tools/package.sh`:

   ```sh
   export DEVELOPER_ID_APPLICATION="Developer ID Application: ..."
   export NOTARYTOOL_PROFILE="buddygotchi-notary"
   export SPARKLE_FRAMEWORK_PATH="/path/to/Sparkle.framework"
   export SPARKLE_PUBLIC_ED_KEY="..."
   ```

   If there is no `NOTARYTOOL_PROFILE`, export `APPLE_ID`, `APPLE_TEAM_ID`, and `APPLE_APP_SPECIFIC_PASSWORD` instead.

2. Package:

   ```sh
   make package
   ```

3. Verify the packaged app:

   ```sh
   codesign --verify --deep --strict build/package/Buddygotchi.app
   spctl -a -t exec -vv build/package/Buddygotchi.app
   xcrun stapler validate build/package/Buddygotchi.app
   ```

4. Generate the appcast after downloading or staging the signed artifacts:

   ```sh
   app/tools/make-appcast.sh <sparkle-bin-dir> <downloads-dir>
   ```

5. Walk the release gates in `research/eng/RELEASE.md`, especially packaged-app smoke from `research/eng/TESTING.md#4-packaged-app-smoke`.

## Final Gates

Before publishing, verify:

- Draft release artifacts launch on a clean Mac.
- Appcast PR updates `/releases/appcast.xml`.
- Firmware manifest hosting is reachable when included in the release.
- `research/eng/RELEASE.md` gates are complete.
- `research/eng/TESTING.md` section 4 packaged-app smoke passes.
