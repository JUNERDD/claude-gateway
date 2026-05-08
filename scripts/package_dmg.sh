#!/usr/bin/env bash
# Build the app and package it as a polished drag-install DMG.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${ROOT}/Info.plist")"
DIST_DIR="${ROOT}/dist"
DMG="${DIST_DIR}/ClaudeGateway-${VERSION}.dmg"
LATEST_DMG="${DIST_DIR}/ClaudeGateway-latest.dmg"
RW_DMG="${DIST_DIR}/ClaudeGateway-${VERSION}-rw.dmg"
VOLNAME="Claude Gateway"
ARCH="$(uname -m)"
OUTDIR="${ROOT}/.build/${ARCH}-apple-macosx/release"
BIN="${OUTDIR}/ClaudeGateway"
PROXY_BIN="${OUTDIR}/GatewayProxy"
BACKGROUND_SRC="${ROOT}/Resources/DMG/background.png"

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

STAGE="$(mktemp -d)"
MOUNT_DIR="/Volumes/${VOLNAME}"
ATTACHED=0

cleanup() {
  if [[ "$ATTACHED" == "1" ]]; then
    hdiutil detach "$MOUNT_DIR" -quiet 2>/dev/null || true
  fi
  rm -rf "$STAGE" "$RW_DMG"
}
trap cleanup EXIT

APP_STAGE="${STAGE}/Claude Gateway.app"

(cd "$ROOT" && swift build -c release)
test -x "$BIN"
test -x "$PROXY_BIN"
test -f "$BACKGROUND_SRC"

mkdir -p "$APP_STAGE/Contents/MacOS" "$APP_STAGE/Contents/Resources"
cp "$BIN" "$APP_STAGE/Contents/MacOS/ClaudeGateway"
chmod +x "$APP_STAGE/Contents/MacOS/ClaudeGateway"
cp "$ROOT/Info.plist" "$APP_STAGE/Contents/Info.plist"
printf 'APPL????' > "$APP_STAGE/Contents/PkgInfo"

if [[ ! -f "$ROOT/Resources/AppIcon.icns" ]]; then
  python3 "$ROOT/scripts/make_app_icon.py" >/dev/null
fi
cp "$ROOT/Resources/AppIcon.icns" "$APP_STAGE/Contents/Resources/AppIcon.icns"
cp "$BACKGROUND_SRC" "$APP_STAGE/Contents/Resources/DmgBackground.png"
cp -R "$ROOT/Resources/Runtime" "$APP_STAGE/Contents/Resources/Runtime"
cp "$PROXY_BIN" "$APP_STAGE/Contents/Resources/Runtime/gateway_proxy"
chmod +x "$APP_STAGE/Contents/Resources/Runtime"/claude-gateway-*.sh
chmod +x "$APP_STAGE/Contents/Resources/Runtime/gateway_proxy"
cp -R "$ROOT/Resources/ClaudeMCPServers" "$APP_STAGE/Contents/Resources/ClaudeMCPServers"
chmod +x "$APP_STAGE/Contents/Resources/ClaudeMCPServers/vision-provider/server.py"

if command -v codesign &>/dev/null; then
  codesign --force --deep --sign - "$APP_STAGE" 2>/dev/null || true
fi

ln -s /Applications "$STAGE/Applications"

hdiutil create \
  -volname "$VOLNAME" \
  -srcfolder "$STAGE" \
  -fs HFS+ \
  -format UDRW \
  -ov \
  "$RW_DMG" >/dev/null

hdiutil detach "$MOUNT_DIR" -quiet 2>/dev/null || true
hdiutil attach "$RW_DMG" \
  -readwrite \
  -noverify \
  -noautoopen >/dev/null
if [[ ! -d "$MOUNT_DIR" ]]; then
  echo "Expected mount point not found: $MOUNT_DIR" >&2
  exit 1
fi
ATTACHED=1

if ! osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$VOLNAME"
    open
    delay 1
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {120, 120, 940, 590}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 96
    set text size of viewOptions to 12
    set background picture of viewOptions to (POSIX file "$MOUNT_DIR/Claude Gateway.app/Contents/Resources/DmgBackground.png" as alias)
    set position of item "Claude Gateway.app" of container window to {210, 235}
    set position of item "Applications" of container window to {613, 235}
    update without registering applications
    delay 2
    close
  end tell
end tell
APPLESCRIPT
then
  if [[ "${CI:-}" == "true" ]]; then
    echo "Finder DMG layout automation is unavailable in CI; continuing with the default volume layout." >&2
  else
    exit 1
  fi
fi

rm -rf "$MOUNT_DIR/.fseventsd" "$MOUNT_DIR/.Trashes"
sync
hdiutil detach "$MOUNT_DIR" -quiet
ATTACHED=0

hdiutil convert "$RW_DMG" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "$DMG" >/dev/null

hdiutil verify "$DMG" >/dev/null
cp "$DMG" "$LATEST_DMG"
echo "DMG created: $DMG"
echo "DMG latest alias created: $LATEST_DMG"
