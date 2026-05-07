#!/usr/bin/env bash
# 编译 SwiftUI 控制台并安装到 ~/Applications/Claude DeepSeek Gateway.app
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="${HOME}/Applications/Claude DeepSeek Gateway.app"
ARCH="$(uname -m)"
OUTDIR="${ROOT}/.build/${ARCH}-apple-macosx/release"
BIN="${OUTDIR}/ClaudeDeepSeekGateway"
PROXY_BIN="${OUTDIR}/DeepSeekAliasProxy"

(cd "$ROOT" && swift build -c release)
test -x "$BIN"
test -x "$PROXY_BIN"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/ClaudeDeepSeekGateway"
chmod +x "$APP/Contents/MacOS/ClaudeDeepSeekGateway"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

mkdir -p "$APP/Contents/Resources"
if [[ ! -f "$ROOT/Resources/AppIcon.icns" ]]; then
  python3 "$ROOT/scripts/make_app_icon.py" >/dev/null
fi
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$APP/Contents/Resources/Runtime"
cp -R "$ROOT/Resources/Runtime" "$APP/Contents/Resources/Runtime"
cp "$PROXY_BIN" "$APP/Contents/Resources/Runtime/deepseek_anthropic_alias_proxy"
chmod +x "$APP/Contents/Resources/Runtime"/claude-deepseek-gateway-*.sh
chmod +x "$APP/Contents/Resources/Runtime/deepseek_anthropic_alias_proxy"
rm -rf "$APP/Contents/Resources/ClaudeMCPServers"
cp -R "$ROOT/Resources/ClaudeMCPServers" "$APP/Contents/Resources/ClaudeMCPServers"
chmod +x "$APP/Contents/Resources/ClaudeMCPServers/vision-provider/server.py"

if command -v codesign &>/dev/null; then
  codesign --force --deep --sign - "$APP" 2>/dev/null || true
fi

echo "已安装: $APP"
