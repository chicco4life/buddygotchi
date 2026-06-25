#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_PATH="${1:-$REPO_ROOT/dist/Buddygotchi.app}"
ENTITLEMENTS="$REPO_ROOT/app/Buddygotchi/Resources/Buddygotchi.entitlements"
IDENTITY="${APPLE_DEVELOPER_IDENTITY:-}"

if [[ -z "$IDENTITY" ]]; then
  echo "APPLE_DEVELOPER_IDENTITY is required, e.g. Developer ID Application: Example Inc (TEAMID)" >&2
  exit 64
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found: $APP_PATH" >&2
  exit 66
fi

sign_item() {
  local item="$1"
  echo "==> Signing $item"
  /usr/bin/codesign --force --timestamp --options runtime --sign "$IDENTITY" "$item"
}

sign_macho_if_needed() {
  local item="$1"
  if /usr/bin/file "$item" | grep -q "Mach-O"; then
    sign_item "$item"
  fi
}

if [[ -d "$APP_PATH/Contents/Frameworks" ]]; then
  while IFS= read -r item; do
    sign_macho_if_needed "$item"
  done < <(find "$APP_PATH/Contents/Frameworks" -type f -perm -111 -print)

  while IFS= read -r item; do
    sign_item "$item"
  done < <(find "$APP_PATH/Contents/Frameworks" \
    \( -name "*.xpc" -o -name "*.app" -o -name "*.framework" -o -name "*.dylib" \) \
    -depth -print)
fi

if [[ -d "$APP_PATH/Contents/Helpers" ]]; then
  while IFS= read -r helper; do
    sign_item "$helper"
  done < <(find "$APP_PATH/Contents/Helpers" -type f -perm -111 -print)
fi

echo "==> Signing app bundle"
/usr/bin/codesign --force --timestamp --options runtime \
  --entitlements "$ENTITLEMENTS" \
  --sign "$IDENTITY" \
  "$APP_PATH"

echo "==> Verifying app signature"
/usr/bin/codesign --verify --deep --strict --verbose=4 "$APP_PATH"
/usr/sbin/spctl --assess --type execute --verbose=4 "$APP_PATH" || true
