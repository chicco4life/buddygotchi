#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_DIR="$ROOT_DIR/app"
BUILD_DIR="$ROOT_DIR/build/package"
APP_NAME="Buddygotchi"
BUNDLE_ID="${BUDDY_BUNDLE_ID:-com.buddygotchi.mac}"
VERSION_FILE="$ROOT_DIR/VERSION"
VERSION="${BUDDY_VERSION:-$(tr -d '[:space:]' < "$VERSION_FILE")}"
VERSION="${VERSION#v}"
BUILD_NUMBER="${BUDDY_BUILD_NUMBER:-$VERSION}"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
FRAMEWORKS="$CONTENTS/Frameworks"
PLIST="$CONTENTS/Info.plist"
ARTIFACTS="$ROOT_DIR/build/artifacts"

rm -rf "$BUILD_DIR" "$ARTIFACTS"
mkdir -p "$MACOS" "$RESOURCES" "$FRAMEWORKS" "$ARTIFACTS"

(
  cd "$APP_DIR"
  swift build -c release
)

BIN_DIR="$(cd "$APP_DIR" && swift build -c release --show-bin-path)"
cp "$BIN_DIR/Buddygotchi" "$MACOS/Buddygotchi"
cp "$BIN_DIR/BuddygotchiSignal" "$MACOS/BuddygotchiSignal"
chmod 755 "$MACOS/Buddygotchi" "$MACOS/BuddygotchiSignal"

cp "$APP_DIR/Buddygotchi/Resources/Info.plist" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$PLIST"

if [[ -f "$APP_DIR/Buddygotchi/Resources/AppIcon.icns" ]]; then
  cp "$APP_DIR/Buddygotchi/Resources/AppIcon.icns" "$RESOURCES/AppIcon.icns"
else
  echo "warning: AppIcon.icns not found; package will use the default app icon" >&2
fi

if [[ -n "${SPARKLE_FRAMEWORK_PATH:-}" ]]; then
  rm -rf "$FRAMEWORKS/Sparkle.framework"
  cp -R "$SPARKLE_FRAMEWORK_PATH" "$FRAMEWORKS/Sparkle.framework"
fi

if [[ -n "${SPARKLE_PUBLIC_ED_KEY:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $SPARKLE_PUBLIC_ED_KEY" "$PLIST"
fi

sign_item() {
  local path="$1"
  if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
    codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_APPLICATION" "$path"
  fi
}

if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
  if [[ -d "$FRAMEWORKS/Sparkle.framework" ]]; then
    sign_if_exists() {
      local path="$1"
      if [[ -e "$path" ]]; then
        sign_item "$path"
      fi
    }
    sign_if_exists "$FRAMEWORKS/Sparkle.framework/Versions/B/XPCServices/Installer.xpc"
    sign_if_exists "$FRAMEWORKS/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc"
    sign_if_exists "$FRAMEWORKS/Sparkle.framework/Versions/B/Autoupdate"
    sign_if_exists "$FRAMEWORKS/Sparkle.framework/Versions/B/Updater.app"
    sign_item "$FRAMEWORKS/Sparkle.framework"
  fi
  sign_item "$MACOS/BuddygotchiSignal"
  sign_item "$MACOS/Buddygotchi"
  codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_APPLICATION" "$APP_BUNDLE"
else
  echo "Built unsigned app bundle. Set DEVELOPER_ID_APPLICATION to sign." >&2
fi

ZIP_PATH="$ARTIFACTS/Buddygotchi-$VERSION.zip"
ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"

if [[ -n "${NOTARYTOOL_PROFILE:-}" && -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
  xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARYTOOL_PROFILE" --wait
  xcrun stapler staple "$APP_BUNDLE"
  ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"
elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" && -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
  xcrun notarytool submit "$ZIP_PATH" \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_SPECIFIC_PASSWORD" \
    --wait
  xcrun stapler staple "$APP_BUNDLE"
  ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"
else
  echo "Skipping notarization. Configure NOTARYTOOL_PROFILE or Apple ID notarization env vars." >&2
fi

if command -v create-dmg >/dev/null 2>&1; then
  DMG_PATH="$ARTIFACTS/Buddygotchi-$VERSION.dmg"
  create-dmg \
    --volname "Buddygotchi" \
    --window-pos 200 120 \
    --window-size 640 420 \
    --icon-size 96 \
    --app-drop-link 440 205 \
    "$DMG_PATH" \
    "$APP_BUNDLE"
  echo "Created $DMG_PATH"
else
  echo "create-dmg not found; zip artifact is ready at $ZIP_PATH" >&2
fi

echo "Created $APP_BUNDLE"
echo "Created $ZIP_PATH"
