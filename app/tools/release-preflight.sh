#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INFO_PLIST="$ROOT_DIR/app/Buddygotchi/Resources/Info.plist"
VERSION_FILE="$ROOT_DIR/VERSION"
SPARKLE_VERSION="2.6.4"
SPARKLE_SHA256="50612a06038abc931f16011d7903b8326a362c1074dabccb718404ce8e585f0b"
SPARKLE_PLACEHOLDER="BUDDYGOTCHI_SPARKLE_PUBLIC_KEY_PLACEHOLDER"

hard_failures=0
warnings=0

pass() {
  printf '✅ PASS  %s\n' "$1"
}

hard_fail() {
  printf '❌ HARD  %s\n' "$1"
  printf '   Fix: %s\n' "$2"
  hard_failures=$((hard_failures + 1))
}

warn_fail() {
  printf '❌ WARN  %s\n' "$1"
  printf '   Fix: %s\n' "$2"
  warnings=$((warnings + 1))
}

read_plist() {
  local key="$1"
  /usr/libexec/PlistBuddy -c "Print :$key" "$INFO_PLIST" 2>/dev/null
}

head_reachable() {
  local url="$1"
  curl -fsSIL --max-time 10 "$url" >/dev/null 2>&1
}

printf 'Buddygotchi release preflight\n'
printf 'Root: %s\n\n' "$ROOT_DIR"

if command -v security >/dev/null 2>&1; then
  identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"
  if printf '%s\n' "$identities" | grep -F 'Developer ID Application' >/dev/null 2>&1; then
    pass "Developer ID Application certificate is installed in the keychain."
  else
    hard_fail "Developer ID Application certificate was not found in the keychain." \
      "Join the Apple Developer Program, install a Developer ID Application certificate, then confirm with security find-identity -v -p codesigning."
  fi

  if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
    if printf '%s\n' "$identities" | grep -F -- "$DEVELOPER_ID_APPLICATION" >/dev/null 2>&1; then
      pass "DEVELOPER_ID_APPLICATION matches an installed signing identity."
    else
      hard_fail "DEVELOPER_ID_APPLICATION is set but does not match an installed identity." \
        "Set DEVELOPER_ID_APPLICATION exactly to the Developer ID Application identity shown by security find-identity -v -p codesigning."
    fi
  else
    hard_fail "DEVELOPER_ID_APPLICATION is not set." \
      "Export DEVELOPER_ID_APPLICATION with the exact Developer ID Application identity used by app/tools/package.sh."
  fi
else
  hard_fail "security tool is unavailable; signing identities cannot be checked." \
    "Run release preflight on macOS with Xcode command line tools installed."
  hard_fail "DEVELOPER_ID_APPLICATION cannot be validated without the keychain identity list." \
    "Install the Developer ID Application certificate and set DEVELOPER_ID_APPLICATION to its exact identity."
fi

if command -v xcrun >/dev/null 2>&1; then
  pass "xcrun is available."
  if xcrun -f notarytool >/dev/null 2>&1; then
    pass "notarytool is available through xcrun."
  else
    hard_fail "notarytool is not available through xcrun." \
      "Install current Xcode command line tools or full Xcode so xcrun -f notarytool succeeds."
  fi
else
  hard_fail "xcrun is not available." \
    "Install Xcode command line tools or full Xcode before cutting a release."
fi

profile_ok=0
if [[ -n "${NOTARYTOOL_PROFILE:-}" ]] && command -v xcrun >/dev/null 2>&1 && xcrun -f notarytool >/dev/null 2>&1; then
  if xcrun notarytool history --keychain-profile "$NOTARYTOOL_PROFILE" >/dev/null 2>&1; then
    profile_ok=1
  fi
fi

if [[ "$profile_ok" -eq 1 ]]; then
  pass "NOTARYTOOL_PROFILE exists and can query notarytool history."
elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]]; then
  pass "Apple ID notarization env vars are set: APPLE_ID, APPLE_TEAM_ID, APPLE_APP_SPECIFIC_PASSWORD."
else
  hard_fail "Notarization credentials are missing or invalid." \
    "Run xcrun notarytool store-credentials and set NOTARYTOOL_PROFILE, or export APPLE_ID, APPLE_TEAM_ID, and APPLE_APP_SPECIFIC_PASSWORD."
fi

if [[ -n "${SPARKLE_FRAMEWORK_PATH:-}" ]]; then
  if [[ -d "$SPARKLE_FRAMEWORK_PATH" && "$(basename "$SPARKLE_FRAMEWORK_PATH")" == "Sparkle.framework" ]]; then
    pass "SPARKLE_FRAMEWORK_PATH points to Sparkle.framework."
  elif [[ -d "$SPARKLE_FRAMEWORK_PATH/Sparkle.framework" ]]; then
    warn_fail "SPARKLE_FRAMEWORK_PATH points to a directory containing Sparkle.framework, not the framework path itself." \
      "Set SPARKLE_FRAMEWORK_PATH=$SPARKLE_FRAMEWORK_PATH/Sparkle.framework so app/tools/package.sh copies the framework correctly."
  else
    warn_fail "SPARKLE_FRAMEWORK_PATH does not contain Sparkle.framework." \
      "Download Sparkle $SPARKLE_VERSION, verify SHA-256 $SPARKLE_SHA256, extract Sparkle.framework, then set SPARKLE_FRAMEWORK_PATH to that framework."
  fi
else
  warn_fail "SPARKLE_FRAMEWORK_PATH is not set." \
    "Download Sparkle $SPARKLE_VERSION from the Sparkle GitHub release, verify SHA-256 $SPARKLE_SHA256, extract Sparkle.framework, then export SPARKLE_FRAMEWORK_PATH."
fi

if [[ -n "${SPARKLE_PUBLIC_ED_KEY:-}" && "${SPARKLE_PUBLIC_ED_KEY:-}" != "$SPARKLE_PLACEHOLDER" ]]; then
  pass "SPARKLE_PUBLIC_ED_KEY is set and is not the plist placeholder."
else
  warn_fail "SPARKLE_PUBLIC_ED_KEY is missing or still set to the placeholder." \
    "Generate Sparkle EdDSA keys with Sparkle's generate_keys tool and export SPARKLE_PUBLIC_ED_KEY before packaging update-capable builds."
fi

version=""
if [[ -f "$VERSION_FILE" ]]; then
  version="$(tr -d '[:space:]' < "$VERSION_FILE")"
  if [[ "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-([0-9A-Za-z-]+)(\.[0-9A-Za-z-]+)*)?(\+([0-9A-Za-z-]+)(\.[0-9A-Za-z-]+)*)?$ ]]; then
    pass "VERSION parses as semver: $version."
  else
    hard_fail "VERSION does not parse as semver: ${version:-<empty>}." \
      "Write VERSION as MAJOR.MINOR.PATCH, for example 0.3.0."
  fi
else
  hard_fail "VERSION file is missing." \
    "Create VERSION at the repo root with the release version, for example 0.3.0."
fi

if git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if [[ -z "$(git -C "$ROOT_DIR" status --porcelain)" ]]; then
    pass "Git tree is clean."
  else
    hard_fail "Git tree is dirty." \
      "Commit, stash, or discard local changes before cutting a production release."
  fi

  branch="$(git -C "$ROOT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  if [[ "$branch" == "main" ]]; then
    pass "Current branch is main."
  else
    hard_fail "Current branch is '$branch', not main." \
      "Check out main and pull the intended release commit before tagging."
  fi

  if [[ -n "$version" ]]; then
    tag="v$version"
    if git -C "$ROOT_DIR" rev-parse -q --verify "refs/tags/$tag" >/dev/null 2>&1; then
      hard_fail "Release tag $tag already exists." \
        "Pick the next VERSION or delete the mistaken local and remote tag only if the release was never published."
    else
      pass "Release tag $tag does not already exist."
    fi
  fi
else
  hard_fail "Repo is not a git work tree." \
    "Run preflight from a Buddygotchi git checkout."
fi

if command -v curl >/dev/null 2>&1; then
  if [[ -x /usr/libexec/PlistBuddy ]]; then
    appcast_url="$(read_plist SUFeedURL || true)"
    firmware_url="$(read_plist BUDDY_FIRMWARE_MANIFEST_URL || true)"

    if [[ -n "$appcast_url" ]]; then
      if head_reachable "$appcast_url"; then
        pass "Sparkle appcast URL is reachable: $appcast_url."
      else
        warn_fail "Sparkle appcast URL is not reachable by HEAD: $appcast_url." \
          "Confirm hosting is live and that RELEASE.md appcast publishing is complete before publishing the release."
      fi
    else
      warn_fail "SUFeedURL is missing from $INFO_PLIST." \
        "Set SUFeedURL in Info.plist to the hosted Sparkle appcast URL."
    fi

    if [[ -n "$firmware_url" ]]; then
      if head_reachable "$firmware_url"; then
        pass "Firmware manifest URL is reachable: $firmware_url."
      else
        warn_fail "Firmware manifest URL is not reachable by HEAD: $firmware_url." \
          "Confirm firmware hosting is live before announcing the release."
      fi
    else
      warn_fail "BUDDY_FIRMWARE_MANIFEST_URL is missing from $INFO_PLIST." \
        "Set BUDDY_FIRMWARE_MANIFEST_URL in Info.plist to the hosted firmware manifest URL."
    fi
  else
    warn_fail "PlistBuddy is unavailable; hosting URLs cannot be read from Info.plist." \
      "Run on macOS with /usr/libexec/PlistBuddy available."
  fi
else
  warn_fail "curl is unavailable; hosting reachability cannot be checked." \
    "Install curl and rerun preflight, or manually HEAD the appcast and firmware manifest URLs."
fi

if command -v create-dmg >/dev/null 2>&1; then
  pass "create-dmg is available for DMG artifacts."
else
  warn_fail "create-dmg is not installed; packaging will fall back to the zip artifact." \
    "Install create-dmg when a DMG is required, or publish the zip artifact produced by app/tools/package.sh."
fi

printf '\nSummary: %d hard failure(s), %d warning(s)\n' "$hard_failures" "$warnings"
if [[ "$hard_failures" -gt 0 ]]; then
  exit 1
fi
