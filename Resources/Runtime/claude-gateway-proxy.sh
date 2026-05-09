#!/usr/bin/env bash
# Claude Desktop gateway -> configured Anthropic-compatible provider.
# Image inputs are saved as local attachments for Claude's bundled vision-provider MCP server.
set -euo pipefail

cd "$HOME"
CFG_DIR="${HOME}/.config/claude-gateway"
CONFIG="${CFG_DIR}/config.json"
PROXY_BIN="${CFG_DIR}/gateway_proxy"

if [[ ! -f "$CONFIG" ]]; then
  echo "缺少 ${CONFIG}，请先运行: claude-gateway-doctor.sh" >&2
  exit 1
fi
if [[ ! -x "$PROXY_BIN" ]]; then
  echo "缺少或不可执行 ${PROXY_BIN}" >&2
  exit 1
fi

LOCAL_GATEWAY_KEY="$(/usr/bin/plutil -extract localGatewayKey raw "$CONFIG" 2>/dev/null || true)"
if [[ -z "$LOCAL_GATEWAY_KEY" ]]; then
  echo "请在 ${CONFIG} 中设置 localGatewayKey" >&2
  exit 1
fi

read_setting() {
  /usr/bin/plutil -extract "$1" raw "$CONFIG" 2>/dev/null || printf '%s\n' "$2"
}

HOST="${GATEWAY_HOST:-$(read_setting host 127.0.0.1)}"
PORT="${GATEWAY_PORT:-$(read_setting port 4000)}"
MODELS_JSON="$(/usr/bin/plutil -extract modelRoutes json -o - "$CONFIG" 2>/dev/null || printf '%s\n' '[]')"
export GATEWAY_HOST="$HOST"
export GATEWAY_PORT="$PORT"
export GATEWAY_CONFIG_PATH="$CONFIG"

echo "Claude Gateway: http://${HOST}:${PORT}"
echo "Claude Desktop Gateway URL: http://${HOST}:${PORT}"
echo "Claude Desktop API Key: （config.json 里的 localGatewayKey）"
echo "配置: ${CONFIG}"
echo "模型路由: ${MODELS_JSON}"
echo "图片链路: 保存为本地附件路径；Claude 通过 vision-provider MCP 调用本机 /v1/vision/describe"
echo ""

if [[ -x "$PROXY_BIN" ]]; then
  exec "$PROXY_BIN"
fi
