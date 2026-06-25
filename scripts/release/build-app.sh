#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 VERSION BUILD_NUMBER" >&2
  echo "Example: $0 0.4.0 123" >&2
}

if [[ $# -ne 2 ]]; then
  usage
  exit 64
fi

VERSION="$1"
BUILD_NUMBER="$2"
APP_NAME="Buddygotchi"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_DIR="$REPO_ROOT/app"
DIST_DIR="$REPO_ROOT/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
HELPERS_DIR="$CONTENTS_DIR/Helpers"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

PRODUCTS=("Buddygotchi" "BuddygotchiHook" "BuddygotchiSignal")

if [[ ! "$VERSION" =~ ^[0-9]+[.][0-9]+[.][0-9]+([-.][A-Za-z0-9.]+)?$ ]]; then
  echo "Version must be semver-like, got: $VERSION" >&2
  exit 64
fi

find_built_product() {
  local name="$1"
  local product
  product="$(find "$APP_DIR/.build" -type f -perm -111 -name "$name" 2>/dev/null \
    | grep -E '/(release|Release)/' \
    | head -n 1 || true)"
  if [[ -z "$product" ]]; then
    echo "Unable to find built product: $name" >&2
    exit 1
  fi
  echo "$product"
}

echo "==> Cleaning dist"
rm -rf "$DIST_DIR"
mkdir -p "$MACOS_DIR" "$HELPERS_DIR" "$FRAMEWORKS_DIR" "$RESOURCES_DIR"

echo "==> Building universal release binaries"
(
  cd "$APP_DIR"
  swift build --configuration release --arch arm64 --arch x86_64
)

echo "==> Assembling $APP_BUNDLE"
install -m 755 "$(find_built_product Buddygotchi)" "$MACOS_DIR/Buddygotchi"
install -m 755 "$(find_built_product BuddygotchiHook)" "$HELPERS_DIR/BuddygotchiHook"
install -m 755 "$(find_built_product BuddygotchiSignal)" "$HELPERS_DIR/BuddygotchiSignal"

cp "$APP_DIR/Buddygotchi/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -replace CFBundleShortVersionString -string "$VERSION" "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$CONTENTS_DIR/Info.plist"

if [[ -n "${SPARKLE_PUBLIC_ED_KEY:-}" ]]; then
  /usr/bin/plutil -replace SUPublicEDKey -string "$SPARKLE_PUBLIC_ED_KEY" "$CONTENTS_DIR/Info.plist"
fi

if [[ -n "${SPARKLE_FEED_URL:-}" ]]; then
  /usr/bin/plutil -replace SUFeedURL -string "$SPARKLE_FEED_URL" "$CONTENTS_DIR/Info.plist"
fi

if [[ -f "$APP_DIR/Buddygotchi/Resources/AppIcon.icns" ]]; then
  cp "$APP_DIR/Buddygotchi/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
  /usr/bin/plutil -replace CFBundleIconFile -string "AppIcon" "$CONTENTS_DIR/Info.plist"
else
  echo "warning: AppIcon.icns not found; release app will use the default app icon" >&2
fi

echo "APPL????" > "$CONTENTS_DIR/PkgInfo"

SPARKLE_FRAMEWORK="$(find "$APP_DIR/.build" -type d -name Sparkle.framework 2>/dev/null | head -n 1 || true)"
if [[ -n "$SPARKLE_FRAMEWORK" ]]; then
  echo "==> Copying Sparkle.framework"
  ditto "$SPARKLE_FRAMEWORK" "$FRAMEWORKS_DIR/Sparkle.framework"
else
  echo "Sparkle.framework not found in SwiftPM artifacts" >&2
  exit 1
fi

echo "==> Validating bundle shape"
/usr/bin/plutil -lint "$CONTENTS_DIR/Info.plist"
for product in "${PRODUCTS[@]}"; do
  if [[ "$product" == "Buddygotchi" ]]; then
    binary="$MACOS_DIR/$product"
  else
    binary="$HELPERS_DIR/$product"
  fi
  test -x "$binary"
  /usr/bin/lipo -info "$binary"
done

echo "Built $APP_BUNDLE"
