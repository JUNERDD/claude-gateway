#!/usr/bin/env bash
# Build the app and package it as a polished drag-install DMG.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${ROOT}/Info.plist")"
DIST_DIR="${ROOT}/dist"
DMG="${DIST_DIR}/ClaudeDeepSeekGateway-${VERSION}.dmg"
RW_DMG="${DIST_DIR}/ClaudeDeepSeekGateway-${VERSION}-rw.dmg"
VOLNAME="Claude DeepSeek Gateway"
ARCH="$(uname -m)"
OUTDIR="${ROOT}/.build/${ARCH}-apple-macosx/release"
BIN="${OUTDIR}/ClaudeDeepSeekGateway"
PROXY_BIN="${OUTDIR}/DeepSeekAliasProxy"

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

STAGE="$(mktemp -d)"
MOUNT_DIR="$(mktemp -d /tmp/claude-deepseek-gateway-dmg.XXXXXX)"
ATTACHED=0

cleanup() {
  if [[ "$ATTACHED" == "1" ]]; then
    hdiutil detach "$MOUNT_DIR" -quiet 2>/dev/null || true
  fi
  rm -rf "$STAGE" "$MOUNT_DIR" "$RW_DMG"
}
trap cleanup EXIT

APP_STAGE="${STAGE}/Claude DeepSeek Gateway.app"

(cd "$ROOT" && swift build -c release)
test -x "$BIN"
test -x "$PROXY_BIN"

mkdir -p "$APP_STAGE/Contents/MacOS" "$APP_STAGE/Contents/Resources"
cp "$BIN" "$APP_STAGE/Contents/MacOS/ClaudeDeepSeekGateway"
chmod +x "$APP_STAGE/Contents/MacOS/ClaudeDeepSeekGateway"
cp "$ROOT/Info.plist" "$APP_STAGE/Contents/Info.plist"
printf 'APPL????' > "$APP_STAGE/Contents/PkgInfo"

if [[ ! -f "$ROOT/Resources/AppIcon.icns" ]]; then
  python3 "$ROOT/scripts/make_app_icon.py" >/dev/null
fi
cp "$ROOT/Resources/AppIcon.icns" "$APP_STAGE/Contents/Resources/AppIcon.icns"
cp -R "$ROOT/Resources/Runtime" "$APP_STAGE/Contents/Resources/Runtime"
cp "$PROXY_BIN" "$APP_STAGE/Contents/Resources/Runtime/deepseek_anthropic_alias_proxy"
chmod +x "$APP_STAGE/Contents/Resources/Runtime"/claude-deepseek-gateway-*.sh
chmod +x "$APP_STAGE/Contents/Resources/Runtime/deepseek_anthropic_alias_proxy"

if command -v codesign &>/dev/null; then
  codesign --force --deep --sign - "$APP_STAGE" 2>/dev/null || true
fi

mkdir -p "$STAGE/.background"
python3 "$ROOT/scripts/make_dmg_background.py" "$STAGE/.background/background.png"
ln -s /Applications "$STAGE/Applications"

hdiutil create \
  -volname "$VOLNAME" \
  -srcfolder "$STAGE" \
  -fs HFS+ \
  -format UDRW \
  -ov \
  "$RW_DMG" >/dev/null

hdiutil attach "$RW_DMG" \
  -readwrite \
  -noverify \
  -noautoopen \
  -mountpoint "$MOUNT_DIR" >/dev/null
ATTACHED=1

osascript <<APPLESCRIPT
tell application "Finder"
  set dmgFolder to (POSIX file "$MOUNT_DIR" as alias)
  open dmgFolder
  delay 1
  set current view of container window of dmgFolder to icon view
  set toolbar visible of container window of dmgFolder to false
  set statusbar visible of container window of dmgFolder to false
  set the bounds of container window of dmgFolder to {120, 120, 880, 550}
  set viewOptions to the icon view options of container window of dmgFolder
  set arrangement of viewOptions to not arranged
  set icon size of viewOptions to 96
  set text size of viewOptions to 12
  set background picture of viewOptions to (POSIX file "$MOUNT_DIR/.background/background.png" as alias)
  set position of item "Claude DeepSeek Gateway.app" of dmgFolder to {210, 225}
  set position of item "Applications" of dmgFolder to {550, 225}
  update dmgFolder without registering applications
  delay 1
  close container window of dmgFolder
end tell
APPLESCRIPT

sync
hdiutil detach "$MOUNT_DIR" -quiet
ATTACHED=0

hdiutil convert "$RW_DMG" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "$DMG" >/dev/null

hdiutil verify "$DMG" >/dev/null
echo "DMG created: $DMG"
