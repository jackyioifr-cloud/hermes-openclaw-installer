#!/usr/bin/env bash
set -euo pipefail

#############################################
# Uninstall Hermes Agent + OpenClaw
# 清除所有安装痕迹
#############################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }

# ── 清除 OpenClaw ──
info "清除 OpenClaw..."
rm -rf /opt/openclaw
rm -f /usr/local/bin/cmdok
rm -f /usr/local/bin/openclaw
info "OpenClaw 已清除 ✓"

# ── 清除 Hermes Agent ──
info "清除 Hermes Agent..."
rm -rf /usr/local/lib/hermes-agent
rm -f /usr/local/bin/hermes
info "Hermes Agent 已清除 ✓"

# ── 清除 uv（如果是脚本安装的）──
if [ -f "$HOME/.local/bin/uv" ]; then
    warn "检测到 uv: $HOME/.local/bin/uv"
    read -r -p "是否也删除 uv? [y/N] " answer
    case "$answer" in
        [yY]|[yY][eE][sS])
            rm -f "$HOME/.local/bin/uv" "$HOME/.local/bin/uvx"
            info "uv 已删除 ✓"
            ;;
        *) info "保留 uv" ;;
    esac
fi

# ── 汇总 ──
echo ""
info "清除完成，以下目录已被删除："
echo "  /opt/openclaw/              (OpenClaw SDK + venv)"
echo "  /usr/local/bin/cmdok        (OpenClaw CLI)"
echo "  /usr/local/bin/openclaw     (OpenClaw wrapper)"
echo "  /usr/local/lib/hermes-agent/ (Hermes 代码 + venv)"
echo "  /usr/local/bin/hermes       (Hermes 命令)"
echo ""
echo "  未删除（保留配置和数据）："
echo "  ~/.hermes/                  (Hermes 配置/会话/日志)"
echo "  如需彻底清除: rm -rf ~/.hermes"
