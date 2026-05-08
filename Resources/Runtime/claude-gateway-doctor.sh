#!/usr/bin/env bash
# 诊断 Claude Desktop ↔ Claude Gateway ↔ configured Anthropic-compatible provider。
set -euo pipefail

if [[ -n "${NO_COLOR:-}" ]] || [[ ! -t 1 ]]; then
  RED=''; GRN=''; YLW=''; NC=''
else
  RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[0;33m'; NC='\033[0m'
fi
info() { printf '%b%s%b\n' "$GRN" "$*" "$NC"; }
warn() { printf '%b%s%b\n' "$YLW" "$*" "$NC"; }
err() { printf '%b%s%b\n' "$RED" "$*" "$NC" >&2; }

cd "$HOME"
CFG_DIR="${HOME}/.config/claude-gateway"
SECRETS="${CFG_DIR}/secrets.json"
SETTINGS="${CFG_DIR}/proxy_settings.json"
BIN_PROXY="${HOME}/bin/claude-gateway-proxy.sh"
PROXY_BIN="${CFG_DIR}/gateway_proxy"

ensure_bin_path() {
  touch "${HOME}/.zshrc"
  if ! grep -q 'claude-gateway PATH' "${HOME}/.zshrc" 2>/dev/null; then
    warn "向 ~/.zshrc 追加 ~/bin 到 PATH（可随时删除该段）"
    {
      echo ''
      echo '# claude-gateway PATH'
      echo 'export PATH="$HOME/bin:$PATH"'
    } >> "${HOME}/.zshrc"
    info "已写入 ~/.zshrc，请执行: source ~/.zshrc"
  fi
}

probe_proxy() {
  local port="$1" key="$2" i code
  for i in $(seq 1 30); do
    code="$(curl -sS -o /dev/null -w '%{http_code}' -H "Authorization: Bearer ${key}" "http://127.0.0.1:${port}/health/liveliness" 2>/dev/null || echo 0)"
    if [[ "$code" == "200" ]]; then
      return 0
    fi
    sleep 1
  done
  return 1
}

read_setting() {
  /usr/bin/plutil -extract "$1" raw "$SETTINGS" 2>/dev/null || printf '%s\n' "$2"
}

read_models_json() {
  python3 - "$SETTINGS" <<'PY' 2>/dev/null || printf '%s\n' '["claude-opus-4-7","claude-sonnet-4-6","claude-haiku-4-5"]'
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as handle:
    data = json.load(handle)
print(json.dumps([route["alias"] for route in data.get("modelRoutes", []) if route.get("alias")]))
PY
}

count_config_library_files() {
  local dir count=0
  for dir in \
    "${HOME}/Library/Application Support/Claude-3p/configLibrary" \
    "${HOME}/Library/Application Support/Claude/configLibrary"; do
    [[ -d "$dir" ]] || continue
    while IFS= read -r _; do
      count=$((count + 1))
    done < <(find "$dir" -maxdepth 1 -type f -name '*.json' \
      ! -name '_meta.json' ! -name '*.tmp' ! -name '*.bak*' ! -name '*bak-*' 2>/dev/null)
  done
  printf '%s\n' "$count"
}

echo "=== claude-gateway doctor ==="

ensure_bin_path
mkdir -p "$HOME/bin" "$CFG_DIR"
chmod 700 "$CFG_DIR" 2>/dev/null || true

if [[ ! -x "$BIN_PROXY" ]]; then
  err "缺少或不可执行: ${BIN_PROXY}"
  exit 1
fi
if [[ ! -x "$PROXY_BIN" ]]; then
  err "缺少或不可执行: ${PROXY_BIN}"
  exit 1
fi
info "原生代理存在: $PROXY_BIN"
info "代理配置: $SETTINGS"

if [[ ! -f "$SECRETS" ]]; then
  err "缺少: $SECRETS"
  exit 1
fi

LOCAL_GATEWAY_KEY="$(/usr/bin/plutil -extract localGatewayKey raw "$SECRETS" 2>/dev/null || true)"
PROVIDER_SECRET_COUNT="$(python3 - "$SECRETS" <<'PY' 2>/dev/null || printf '0\n'
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as handle:
    data = json.load(handle)
print(sum(1 for secret in data.get("providerSecrets", {}).values() if str(secret.get("apiKey", "")).strip()))
PY
)"
VISION_PROVIDER_API_KEY="$(/usr/bin/plutil -extract visionProviderAPIKey raw "$SECRETS" 2>/dev/null || true)"
if [[ "$PROVIDER_SECRET_COUNT" == "0" ]]; then
  warn "未发现 provider API key；请在 ${SECRETS} 的 providerSecrets 中配置上游凭据。"
else
  info "已发现 providerSecrets（未显示具体值）。"
fi
if [[ -z "$VISION_PROVIDER_API_KEY" ]]; then
  warn "VISION_PROVIDER_API_KEY 未设置；gateway 文本请求不受影响，vision-provider MCP 可能需要额外配置。"
else
  info "Vision Provider API Key 已设置（供 gateway-backed vision-provider MCP 使用）。"
fi

if [[ -z "${LOCAL_GATEWAY_KEY:-}" ]]; then
  warn "LOCAL_GATEWAY_KEY 为空，Claude Desktop 将无法通过本地代理鉴权。"
else
  info "LOCAL_GATEWAY_KEY 已设置。"
fi

CFG_HOST="$(read_setting host 127.0.0.1)"
CFG_PORT="$(read_setting port 4000)"
VISION_PROVIDER="$(read_setting visionProvider auto)"
VISION_PROVIDER_MODEL="$(read_setting visionProviderModel '')"
VISION_PROVIDER_BASE_URL="$(read_setting visionProviderBaseURL '')"
MODELS_JSON="$(read_models_json)"

if command -v lsof &>/dev/null; then
  if lsof -iTCP:"$CFG_PORT" -sTCP:LISTEN -n -P &>/dev/null; then
    info "端口 ${CFG_PORT} 已有进程监听。"
    lsof -iTCP:"$CFG_PORT" -sTCP:LISTEN -n -P || true
  elif [[ -z "${CLAUDE_GATEWAY_SUPPRESS_PORT_HINT:-}" ]]; then
    warn "端口 ${CFG_PORT} 当前无监听。请先运行: claude-gateway-proxy.sh"
  fi
fi

TEST_PORT=$((41000 + RANDOM % 500))
export LOCAL_GATEWAY_KEY="${LOCAL_GATEWAY_KEY:-sk-doctor-test}"
info "冒烟测试：端口 ${TEST_PORT}（最多等待约 30s）…"
GATEWAY_HOST=127.0.0.1 GATEWAY_PORT="$TEST_PORT" "$BIN_PROXY" >/tmp/claude-gateway-doctor.log 2>&1 &
DPID=$!

cleanup() { kill "$DPID" 2>/dev/null || true; wait "$DPID" 2>/dev/null || true; }
trap cleanup EXIT

if probe_proxy "$TEST_PORT" "$LOCAL_GATEWAY_KEY"; then
  info "本地代理与 /health/liveliness 正常。"
else
  err "本地代理未在 30s 内就绪。日志尾部:"
  tail -60 /tmp/claude-gateway-doctor.log || true
  exit 1
fi

mc=$(curl -sS -o /tmp/claude-gateway-models.json -w '%{http_code}' \
  -H "Authorization: Bearer ${LOCAL_GATEWAY_KEY}" \
  "http://127.0.0.1:${TEST_PORT}/v1/models" 2>/dev/null || echo "0")
if [[ "$mc" == "200" ]]; then
  info "GET /v1/models -> HTTP ${mc}（Cowork 可用其自动发现模型）"
else
  warn "GET /v1/models -> HTTP ${mc}（自动发现可能失败，请在配置里设置 inferenceModels）"
fi

tc=$(curl -sS -o /tmp/claude-gateway-tokens.json -w '%{http_code}' \
  -H "Authorization: Bearer ${LOCAL_GATEWAY_KEY}" \
  -H "content-type: application/json" \
  --data '{"model":"claude-haiku-4-5","messages":[{"role":"user","content":"ping"}]}' \
  "http://127.0.0.1:${TEST_PORT}/v1/messages/count_tokens?beta=true" 2>/dev/null || echo "0")
if [[ "$tc" == "200" ]]; then
  info "POST /v1/messages/count_tokens -> HTTP ${tc}"
else
  warn "POST /v1/messages/count_tokens -> HTTP ${tc}"
fi

vc=$(curl -sS -o /tmp/claude-gateway-vision.json -w '%{http_code}' \
  -H "Authorization: Bearer ${LOCAL_GATEWAY_KEY}" \
  -H "content-type: application/json" \
  --data '{"prompt":"doctor route probe"}' \
  "http://127.0.0.1:${TEST_PORT}/v1/vision/describe" 2>/dev/null || echo "0")
if [[ "$vc" == "400" ]]; then
  info "POST /v1/vision/describe -> HTTP ${vc}（路由已加载，未真实调用 provider）"
else
  warn "POST /v1/vision/describe -> HTTP ${vc}"
fi

echo ""
info "Claude 3P 配置："
echo "  inferenceGatewayBaseUrl: http://${CFG_HOST}:${CFG_PORT}"
echo "  inferenceGatewayAuthScheme: bearer"
echo "  inferenceGatewayApiKey: 与 LOCAL_GATEWAY_KEY 相同"
echo "  inferenceModels: ${MODELS_JSON}"
echo "  configLibrary 可识别配置文件数: $(count_config_library_files)"
if [[ -f "${HOME}/.claude/cache/gateway-models.json" ]]; then
  warn "检测到旧 gateway 模型缓存: ~/.claude/cache/gateway-models.json（app 保存/启动时会自动刷新）"
else
  info "gateway 模型缓存未发现旧文件。"
fi

echo ""
info "Claude Code 配置："
if [[ -f "${HOME}/.claude/settings.json" ]]; then
  cc_base="$(
    /usr/bin/plutil -extract env.ANTHROPIC_BASE_URL raw "${HOME}/.claude/settings.json" 2>/dev/null || true
  )"
  cc_token="$(
    /usr/bin/plutil -extract env.ANTHROPIC_AUTH_TOKEN raw "${HOME}/.claude/settings.json" 2>/dev/null || true
  )"
  cc_model="$(
    /usr/bin/plutil -extract model raw "${HOME}/.claude/settings.json" 2>/dev/null || true
  )"
  echo "  ANTHROPIC_BASE_URL: ${cc_base:-未设置}"
  echo "  ANTHROPIC_AUTH_TOKEN: $([[ -n "${cc_token:-}" ]] && printf '已设置' || printf '未设置')"
  echo "  model: ${cc_model:-未设置}"
  if [[ "${cc_base:-}" == "http://${CFG_HOST}:${CFG_PORT}" ]]; then
    info "Claude Code base URL 已指向本地 gateway。"
  else
    warn "Claude Code base URL 未指向本地 gateway（app 保存/同步时会自动写入）。"
  fi
  if [[ -n "${LOCAL_GATEWAY_KEY:-}" && "${cc_token:-}" == "${LOCAL_GATEWAY_KEY}" ]]; then
    info "Claude Code bearer token 已匹配 LOCAL_GATEWAY_KEY。"
  else
    warn "Claude Code bearer token 未匹配 LOCAL_GATEWAY_KEY（app 保存/同步时会自动写入）。"
  fi
else
  warn "未发现 ~/.claude/settings.json（app 保存/同步时会自动创建 Claude Code 配置）。"
fi

echo ""
info "Claude MCP："
VISION_MCP="${HOME}/.claude/mcp/vision-provider"
if [[ -L "$VISION_MCP" ]]; then
  echo "  vision-provider MCP -> $(readlink "$VISION_MCP")"
  if [[ -f "${VISION_MCP}/server.py" ]]; then
    info "vision-provider MCP Server 已通过软链接安装。"
  else
    warn "vision-provider MCP Server 软链接目标不存在（app 保存/同步时会修复）。"
  fi
elif [[ -e "$VISION_MCP" ]]; then
  warn "vision-provider MCP 已存在但不是软链接（app 保存/同步时会备份并替换）。"
else
  warn "未发现 vision-provider MCP Server（app 保存/同步时会自动软链接）。"
fi
echo ""
info "当前代理使用显式模型路由，并把图片保存成本地路径供 MCP 主动识别:"
echo "  modelRoutes: ${MODELS_JSON}"
if [[ -n "$VISION_PROVIDER_MODEL" || "$VISION_PROVIDER" != "auto" ]]; then
  info "vision-provider MCP 默认配置:"
  echo "  Vision Provider        -> ${VISION_PROVIDER}"
  echo "  Vision Model           -> ${VISION_PROVIDER_MODEL:-未设置}"
  echo "  Vision Base URL        -> ${VISION_PROVIDER_BASE_URL:-默认}"
else
  warn "Vision Provider 未配置；vision-provider MCP 会按环境变量自动选择 provider。"
fi
