#!/usr/bin/env bash
set -euo pipefail

#############################################
# Install Hermes Agent + OpenClaw
# - 两个项目分别安装到独立目录
# - 仅安装，不配置
# - 使用官方 curl 安装命令
#############################################

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }

# ── 安装 Hermes Agent ──
info "安装 Hermes Agent → /usr/local/lib/hermes-agent/"
curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash -s -- --skip-setup --skip-browser || warn "Hermes 安装失败"
info "Hermes Agent 完成 ✓"

# ── 安装 OpenClaw CLI ──
info "安装 OpenClaw → /usr/local/bin/cmdok"
curl -fsSL https://cmdop.com/install-cli.sh | bash || warn "OpenClaw 安装失败"
info "OpenClaw 完成 ✓"

# ── 汇总 ──
echo ""
info "=========================================="
info "安装汇总"
info "=========================================="
echo "  Hermes Agent  → /usr/local/lib/hermes-agent/"
echo "  OpenClaw CLI  → /usr/local/bin/cmdok"
echo ""
echo "  配置 Hermes:  hermes setup"
echo "  使用 OpenClaw: cmdok ssh"
