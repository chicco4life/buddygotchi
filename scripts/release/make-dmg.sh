#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 VERSION" >&2
}

if [[ $# -ne 1 ]]; then
  usage
  exit 64
fi

VERSION="$1"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DIST_DIR="$REPO_ROOT/dist"
APP_PATH="$DIST_DIR/Buddygotchi.app"
STAGING_DIR="$DIST_DIR/dmg-staging"
DMG_PATH="$DIST_DIR/Buddygotchi-$VERSION.dmg"
VOLUME_NAME="Buddygotchi"

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found: $APP_PATH" >&2
  exit 66
fi

rm -rf "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$STAGING_DIR"

echo "==> Staging DMG contents"
ditto "$APP_PATH" "$STAGING_DIR/Buddygotchi.app"
ln -s /Applications "$STAGING_DIR/Applications"

echo "==> Creating $DMG_PATH"
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

if [[ -n "${APPLE_DEVELOPER_IDENTITY:-}" ]]; then
  echo "==> Signing DMG"
  /usr/bin/codesign --force --timestamp --sign "$APPLE_DEVELOPER_IDENTITY" "$DMG_PATH"
fi

hdiutil verify "$DMG_PATH"
echo "Created $DMG_PATH"
