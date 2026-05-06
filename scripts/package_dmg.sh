#!/usr/bin/env bash
# Build the app and package it as a simple drag-install DMG.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${HOME}/Applications/Claude DeepSeek Gateway.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${ROOT}/Info.plist")"
DIST_DIR="${ROOT}/dist"
DMG="${DIST_DIR}/ClaudeDeepSeekGateway-${VERSION}.dmg"
VOLNAME="Claude DeepSeek Gateway"

"${ROOT}/build-and-install-app.sh"

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

STAGE="$(mktemp -d)"
cleanup() {
  rm -rf "$STAGE"
}
trap cleanup EXIT

cp -R "$APP" "$STAGE/Claude DeepSeek Gateway.app"
ln -s /Applications "$STAGE/Applications"

hdiutil create \
  -volname "$VOLNAME" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "$DMG"

hdiutil verify "$DMG" >/dev/null
echo "DMG created: $DMG"
