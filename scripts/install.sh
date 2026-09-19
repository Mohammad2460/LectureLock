#!/bin/bash
# Builds LectureLock in Release and installs it to /Applications.
#
# Pass a code-signing identity to keep the Accessibility grant across rebuilds:
#   ./scripts/install.sh "LectureLock Dev"
# With no argument the app is signed ad-hoc, which is fine as long as you do not
# rebuild (macOS drops the Accessibility grant when the signature changes).

set -euo pipefail

cd "$(dirname "$0")/.."

IDENTITY="${1:-}"
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

ARGS=(
  -project LectureLock.xcodeproj
  -scheme LectureLock
  -configuration Release
  -derivedDataPath "$BUILD_DIR"
)

if [ -n "$IDENTITY" ]; then
  ARGS+=(CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=$IDENTITY" DEVELOPMENT_TEAM="")
fi

echo "Building LectureLock (Release)…"
xcodebuild "${ARGS[@]}" build >/dev/null

APP="$BUILD_DIR/Build/Products/Release/LectureLock.app"
[ -d "$APP" ] || { echo "Build produced no app bundle" >&2; exit 1; }

if [ -d /Applications/LectureLock.app ]; then
  echo "Replacing the existing /Applications/LectureLock.app…"
  pkill -x LectureLock || true
  rm -rf /Applications/LectureLock.app
fi

cp -R "$APP" /Applications/
echo "Installed to /Applications/LectureLock.app"
codesign -dv --verbose=2 /Applications/LectureLock.app 2>&1 | grep -E "Authority|flags" || true

open /Applications/LectureLock.app
echo
echo "Next: click the menu-bar lock icon, grant Accessibility, and tick"
echo "\"Open LectureLock at login\" if you want it to start automatically."
