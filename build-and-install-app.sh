#!/usr/bin/env bash
# 编译 SwiftUI 控制台并安装到 ~/Applications/Claude Gateway.app
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="${HOME}/Applications/Claude Gateway.app"
ARCH="$(uname -m)"
OUTDIR="${ROOT}/.build/${ARCH}-apple-macosx/release"
BIN="${OUTDIR}/ClaudeGateway"
PROXY_BIN="${OUTDIR}/GatewayProxy"

(cd "$ROOT" && swift build -c release)
test -x "$BIN"
test -x "$PROXY_BIN"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/ClaudeGateway"
chmod +x "$APP/Contents/MacOS/ClaudeGateway"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

mkdir -p "$APP/Contents/Resources"
if [[ ! -f "$ROOT/Resources/AppIcon.icns" ]]; then
  python3 "$ROOT/scripts/make_app_icon.py" >/dev/null
fi
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$APP/Contents/Resources/Runtime"
cp -R "$ROOT/Resources/Runtime" "$APP/Contents/Resources/Runtime"
cp "$PROXY_BIN" "$APP/Contents/Resources/Runtime/gateway_proxy"
chmod +x "$APP/Contents/Resources/Runtime"/claude-gateway-*.sh
chmod +x "$APP/Contents/Resources/Runtime/gateway_proxy"
rm -rf "$APP/Contents/Resources/ClaudeMCPServers"
cp -R "$ROOT/Resources/ClaudeMCPServers" "$APP/Contents/Resources/ClaudeMCPServers"
chmod +x "$APP/Contents/Resources/ClaudeMCPServers/vision-provider/server.py"

if command -v codesign &>/dev/null; then
  codesign --force --deep --sign - "$APP" 2>/dev/null || true
fi

echo "已安装: $APP"
