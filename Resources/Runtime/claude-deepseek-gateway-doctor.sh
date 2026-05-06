#!/usr/bin/env bash
# 诊断 Claude Desktop ↔ 本地模型别名代理 ↔ DeepSeek Anthropic API。
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
CFG_DIR="${HOME}/.config/claude-deepseek-gateway"
SECRETS="${CFG_DIR}/secrets.env"
SETTINGS="${CFG_DIR}/proxy_settings.json"
BIN_PROXY="${HOME}/bin/claude-deepseek-gateway-proxy.sh"
PROXY_BIN="${CFG_DIR}/deepseek_anthropic_alias_proxy"

ensure_bin_path() {
  touch "${HOME}/.zshrc"
  if ! grep -q 'claude-deepseek-gateway PATH' "${HOME}/.zshrc" 2>/dev/null; then
    warn "向 ~/.zshrc 追加 ~/bin 到 PATH（可随时删除该段）"
    {
      echo ''
      echo '# claude-deepseek-gateway PATH'
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
  /usr/bin/plutil -extract advertisedModels json -o - "$SETTINGS" 2>/dev/null \
    || printf '%s\n' '["claude-opus-4-7","claude-sonnet-4-6","claude-haiku-4-5"]'
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

echo "=== claude-deepseek-gateway doctor ==="

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

# shellcheck disable=SC1090
source "$SECRETS" || true
if [[ -z "${DEEPSEEK_API_KEY:-}" || "$DEEPSEEK_API_KEY" == "replace_me" ]]; then
  warn "DEEPSEEK_API_KEY 未设置或为占位符 replace_me。"
  warn "请编辑: $SECRETS （填入 DeepSeek 控制台 API Key）"
else
  info "DEEPSEEK_API_KEY 已非占位符。"
fi

if [[ -z "${LOCAL_GATEWAY_KEY:-}" ]]; then
  warn "LOCAL_GATEWAY_KEY 为空，Claude Desktop 将无法通过本地代理鉴权。"
else
  info "LOCAL_GATEWAY_KEY 已设置。"
fi

CFG_HOST="$(read_setting host 127.0.0.1)"
CFG_PORT="$(read_setting port 4000)"
HAIKU_TARGET="$(read_setting haikuTargetModel deepseek-v4-flash)"
OTHER_TARGET="$(read_setting nonHaikuTargetModel 'deepseek-v4-pro[1m]')"
MODELS_JSON="$(read_models_json)"

if command -v lsof &>/dev/null; then
  if lsof -iTCP:"$CFG_PORT" -sTCP:LISTEN -n -P &>/dev/null; then
    info "端口 ${CFG_PORT} 已有进程监听。"
    lsof -iTCP:"$CFG_PORT" -sTCP:LISTEN -n -P || true
  elif [[ -z "${CLAUDE_DEEPSEEK_GATEWAY_SUPPRESS_PORT_HINT:-}" ]]; then
    warn "端口 ${CFG_PORT} 当前无监听。请先运行: claude-deepseek-gateway-proxy.sh"
  fi
fi

TEST_PORT=$((41000 + RANDOM % 500))
export DEEPSEEK_API_KEY="${DEEPSEEK_API_KEY:-x}"
export LOCAL_GATEWAY_KEY="${LOCAL_GATEWAY_KEY:-sk-doctor-test}"
if [[ "$DEEPSEEK_API_KEY" == "replace_me" ]]; then
  export DEEPSEEK_API_KEY="x"
fi

info "冒烟测试：端口 ${TEST_PORT}（最多等待约 30s）…"
GATEWAY_HOST=127.0.0.1 GATEWAY_PORT="$TEST_PORT" "$BIN_PROXY" >/tmp/claude-deepseek-gateway-doctor.log 2>&1 &
DPID=$!

cleanup() { kill "$DPID" 2>/dev/null || true; wait "$DPID" 2>/dev/null || true; }
trap cleanup EXIT

if probe_proxy "$TEST_PORT" "$LOCAL_GATEWAY_KEY"; then
  info "本地代理与 /health/liveliness 正常。"
else
  err "本地代理未在 30s 内就绪。日志尾部:"
  tail -60 /tmp/claude-deepseek-gateway-doctor.log || true
  exit 1
fi

mc=$(curl -sS -o /tmp/claude-deepseek-gateway-models.json -w '%{http_code}' \
  -H "Authorization: Bearer ${LOCAL_GATEWAY_KEY}" \
  "http://127.0.0.1:${TEST_PORT}/v1/models" 2>/dev/null || echo "0")
if [[ "$mc" == "200" ]]; then
  info "GET /v1/models -> HTTP ${mc}（Cowork 可用其自动发现模型）"
else
  warn "GET /v1/models -> HTTP ${mc}（自动发现可能失败，请在配置里设置 inferenceModels）"
fi

tc=$(curl -sS -o /tmp/claude-deepseek-gateway-tokens.json -w '%{http_code}' \
  -H "Authorization: Bearer ${LOCAL_GATEWAY_KEY}" \
  -H "content-type: application/json" \
  --data '{"model":"claude-haiku-4-5","messages":[{"role":"user","content":"ping"}]}' \
  "http://127.0.0.1:${TEST_PORT}/v1/messages/count_tokens?beta=true" 2>/dev/null || echo "0")
if [[ "$tc" == "200" ]]; then
  info "POST /v1/messages/count_tokens -> HTTP ${tc}"
else
  warn "POST /v1/messages/count_tokens -> HTTP ${tc}"
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
info "当前代理只做模型名改写，其余 Anthropic Messages 请求体由 DeepSeek 官方 /anthropic 端点处理:"
echo "  任意包含 haiku 的模型 -> ${HAIKU_TARGET}"
echo "  其他所有模型           -> ${OTHER_TARGET}"
