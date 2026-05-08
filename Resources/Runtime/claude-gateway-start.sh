#!/usr/bin/env bash
# 先诊断，再启动常驻代理（等价于依次执行 doctor + proxy）
set -euo pipefail
# 随后即将启动常驻 proxy，避免 doctor 误判「请先运行 proxy」造成噪音
export CLAUDE_GATEWAY_SUPPRESS_PORT_HINT=1
"$HOME/bin/claude-gateway-doctor.sh"
exec "$HOME/bin/claude-gateway-proxy.sh"
