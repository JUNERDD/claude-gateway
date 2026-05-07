#!/usr/bin/env bash
# Claude Desktop gateway -> DeepSeek Anthropic API.
# Image inputs are saved as local attachments for Claude's bundled vision-provider MCP server.
set -euo pipefail

cd "$HOME"
CFG_DIR="${HOME}/.config/claude-deepseek-gateway"
SECRETS="${CFG_DIR}/secrets.env"
SETTINGS="${CFG_DIR}/proxy_settings.json"
PROXY_BIN="${CFG_DIR}/deepseek_anthropic_alias_proxy"

if [[ ! -f "$SECRETS" ]]; then
  echo "缺少 ${SECRETS}，请先运行: claude-deepseek-gateway-doctor.sh" >&2
  exit 1
fi
if [[ ! -x "$PROXY_BIN" ]]; then
  echo "缺少或不可执行 ${PROXY_BIN}" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$SECRETS"
set +a

if [[ -z "${DEEPSEEK_API_KEY:-}" || "$DEEPSEEK_API_KEY" == "replace_me" ]]; then
  echo "请在 ${SECRETS} 中设置有效的 DEEPSEEK_API_KEY" >&2
  exit 1
fi
if [[ -z "${LOCAL_GATEWAY_KEY:-}" ]]; then
  echo "请在 ${SECRETS} 中设置 LOCAL_GATEWAY_KEY" >&2
  exit 1
fi

read_setting() {
  /usr/bin/plutil -extract "$1" raw "$SETTINGS" 2>/dev/null || printf '%s\n' "$2"
}

HOST="${GATEWAY_HOST:-$(read_setting host 127.0.0.1)}"
PORT="${GATEWAY_PORT:-$(read_setting port 4000)}"
HAIKU_TARGET="$(read_setting haikuTargetModel deepseek-v4-flash)"
OTHER_TARGET="$(read_setting nonHaikuTargetModel 'deepseek-v4-pro[1m]')"
export GATEWAY_HOST="$HOST"
export GATEWAY_PORT="$PORT"

echo "Claude DeepSeek Gateway: http://${HOST}:${PORT}"
echo "Claude Desktop Gateway URL: http://${HOST}:${PORT}"
echo "Claude Desktop API Key: （secrets.env 里的 LOCAL_GATEWAY_KEY）"
echo "配置: ${SETTINGS}"
echo "映射: *haiku* -> ${HAIKU_TARGET}; 其他模型 -> ${OTHER_TARGET}"
echo "图片链路: 保存为本地附件路径；Claude 通过 vision-provider MCP 调用本机 /v1/vision/describe"
echo ""

if [[ -x "$PROXY_BIN" ]]; then
  exec "$PROXY_BIN"
fi
