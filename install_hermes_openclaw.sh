#!/usr/bin/env bash
set -euo pipefail

#############################################
# Install Hermes Agent + OpenClaw
# - 两个项目分别安装到独立目录
# - 仅安装，不配置
# - 使用官方 curl 安装命令
#############################################

# ── 颜色 ──
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# ── 前置检查 ──
info "检查系统依赖..."

if ! command -v curl &>/dev/null; then
    warn "curl 未安装，自动安装中..."
    apt-get update -qq && apt-get install -y -qq curl
    if ! command -v curl &>/dev/null; then
        error "curl 自动安装失败，请手动安装: apt install -y curl"
    fi
fi
info "curl ✓"

if ! command -v git &>/dev/null; then
    warn "git 未安装，自动安装中..."
    apt-get update -qq && apt-get install -y -qq git
    if ! command -v git &>/dev/null; then
        error "git 自动安装失败，请手动安装: apt install -y git"
    fi
fi
info "git ✓"

# Python 版本检查 (Hermes 需要 >=3.11)
if ! command -v python3 &>/dev/null; then
    warn "python3 未安装，自动安装中..."
    apt-get update -qq && apt-get install -y -qq python3 python3-venv python3-pip
    if ! command -v python3 &>/dev/null; then
        error "python3 自动安装失败，请手动安装: apt install -y python3"
    fi
fi

PY_VER=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null || echo "0.0")
PY_MAJOR=$(echo "$PY_VER" | cut -d. -f1)
PY_MINOR=$(echo "$PY_VER" | cut -d. -f2)

if [ "$PY_MAJOR" -lt 3 ] || { [ "$PY_MAJOR" -eq 3 ] && [ "$PY_MINOR" -lt 11 ]; }; then
    warn "Python ${PY_VER} < 3.11，Hermes 官方安装脚本会通过 uv 自动安装 Python 3.11"
fi
info "Python ${PY_VER} ✓"

# ── 安装 Hermes Agent ──
info "=========================================="
info "安装 Hermes Agent"
info "=========================================="
info "使用官方安装脚本 (默认路径: root → /usr/local/lib/hermes-agent)"
info "安装到: ${HERMES_INSTALL_DIR:-/usr/local/lib/hermes-agent}"

curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash -s -- --skip-setup --skip-browser

info "Hermes Agent 安装完成 ✓"

# ── 安装 OpenClaw ──
info "=========================================="
info "安装 OpenClaw (cmdok CLI)"
info "=========================================="
info "使用官方安装脚本 (默认路径: /usr/local/bin/cmdok)"

curl -fsSL https://cmdop.com/install-cli.sh | bash

info "OpenClaw 安装完成 ✓"

# ── 安装 OpenClaw Python SDK ──
info "=========================================="
info "安装 OpenClaw Python SDK"
info "=========================================="

OPENCLAW_DIR="/opt/openclaw"

info "创建独立 venv → ${OPENCLAW_DIR}/venv/"
mkdir -p "${OPENCLAW_DIR}"

if command -v uv &>/dev/null; then
    uv venv "${OPENCLAW_DIR}/venv" --python python3
    uv pip install --python "${OPENCLAW_DIR}/venv/bin/python" openclaw tenacity
elif command -v python3 &>/dev/null; then
    python3 -m venv "${OPENCLAW_DIR}/venv"
    "${OPENCLAW_DIR}/venv/bin/python" -m ensurepip
    "${OPENCLAW_DIR}/venv/bin/pip" install openclaw tenacity
else
    error "没有 uv 或 python3，无法创建 venv"
fi

info "OpenClaw Python SDK 安装完成 ✓"

# ── 验证 ──
info "=========================================="
info "验证安装"
info "=========================================="

echo ""

HERMES_OK="✗"
if command -v hermes &>/dev/null; then
    HERMES_VER=$(hermes --version 2>&1 | head -1)
    HERMES_OK="✓"
    info "Hermes Agent: ${HERMES_VER} ✓"
else
    warn "hermes 命令未找到"
fi

CMDOK_OK="✗"
if command -v cmdok &>/dev/null; then
    CMDOK_VER=$(cmdok --version 2>&1 | head -1)
    CMDOK_OK="✓"
    info "cmdok CLI: ${CMDOK_VER} ✓"
else
    warn "cmdok 命令未找到"
fi

OPENCLAW_PY_OK="✗"
if "${OPENCLAW_DIR}/venv/bin/python" -c "import cmdop; print('cmdop OK')" 2>/dev/null; then
    OPENCLAW_PY_OK="✓"
    info "OpenClaw Python SDK (cmdop): import 验证 ✓"
else
    warn "OpenClaw Python SDK import 失败"
fi

# ── 汇总 ──
echo ""
info "=========================================="
info "安装汇总"
info "=========================================="
echo ""
echo "  Hermes Agent    ${HERMES_OK}"
echo "    代码目录:      /usr/local/lib/hermes-agent/"
echo "    venv:          /usr/local/lib/hermes-agent/venv/"
echo "    命令:          hermes"
echo "    配置:          ~/.hermes/config.yaml"
echo ""
echo "  OpenClaw CLI    ${CMDOK_OK}"
echo "    二进制:        /usr/local/bin/cmdok"
echo ""
echo "  OpenClaw SDK    ${OPENCLAW_PY_OK}"
echo "    目录:          /opt/openclaw/"
echo "    venv:          /opt/openclaw/venv/"
echo "    使用:          source /opt/openclaw/venv/bin/activate"
echo ""
echo "  两个项目独立安装，互不影响。"
echo "  如需配置 Hermes，运行: hermes setup"
