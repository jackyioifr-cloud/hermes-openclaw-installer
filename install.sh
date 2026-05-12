#!/bin/bash
set -e

# ============================================================
# 双Agent本地一键安装脚本：OpenClaw + Hermes Agent
# 适用：Debian 13, root 用户（直接在目标服务器运行）
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}   $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ============================================================
# 1. 交互输入
# ============================================================
echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}  双Agent一键部署：OpenClaw + Hermes  ${NC}"
echo -e "${BLUE}======================================${NC}"
echo ""

read -p "DashScope API Key: " API_KEY
while [ -z "$API_KEY" ]; do
  log_error "API Key 不能为空"
  read -p "DashScope API Key: " API_KEY
done

read -p "OpenClaw Telegram Bot Token: " OPENCLAW_BOT_TOKEN
while [ -z "$OPENCLAW_BOT_TOKEN" ]; do
  log_error "Bot Token 不能为空"
  read -p "OpenClaw Telegram Bot Token: " OPENCLAW_BOT_TOKEN
done

echo ""
echo "请选择 Hermes 部署模式："
echo "  [1] CLI集成模式（推荐）：OpenClaw 调用 Hermes 处理复杂任务"
echo "  [2] 独立Bot模式：Hermes 拥有独立的 Telegram Bot"
read -p "选择 [1]: " MODE_CHOICE
MODE_CHOICE=${MODE_CHOICE:-1}

echo ""
read -p "模型 Provider ID (OpenClaw 使用) [dashscope]: " PROVIDER_ID
PROVIDER_ID=${PROVIDER_ID:-dashscope}

read -p "模型名称 [qwen3.6-plus]: " MODEL_NAME
MODEL_NAME=${MODEL_NAME:-qwen3.6-plus}

read -p "API Base URL [https://coding.dashscope.aliyuncs.com/v1]: " MODEL_BASE_URL
MODEL_BASE_URL=${MODEL_BASE_URL:-https://coding.dashscope.aliyuncs.com/v1}

read -p "Context Window (token) [128000]: " CONTEXT_WINDOW
CONTEXT_WINDOW=${CONTEXT_WINDOW:-128000}


HERMES_BOT_TOKEN=""
if [ "$MODE_CHOICE" = "2" ]; then
  read -p "Hermes 独立 Telegram Bot Token: " HERMES_BOT_TOKEN
  while [ -z "$HERMES_BOT_TOKEN" ]; do
    log_error "Bot Token 不能为空"
    read -p "Hermes 独立 Telegram Bot Token: " HERMES_BOT_TOKEN
  done
fi

# ============================================================
# 2. 安装 Docker
# ============================================================
log_info "安装 Docker..."
if command -v docker >/dev/null 2>&1; then
  log_ok "Docker 已安装"
else
  curl -fsSL https://get.docker.com | bash
  systemctl enable docker && systemctl start docker
  log_ok "Docker 安装完成"
fi

# ============================================================
# 3. 安装 OpenClaw
# ============================================================
log_info "安装 OpenClaw..."
if command -v openclaw >/dev/null 2>&1; then
  log_ok "OpenClaw 已安装"
  openclaw --version
else
  curl -fsSL https://openclaw.ai/install.sh | bash
  log_ok "OpenClaw 安装完成"
  openclaw --version
fi

# ============================================================
# 4. 安装 Hermes Agent
# ============================================================
log_info "安装 Hermes Agent..."
if command -v hermes >/dev/null 2>&1; then
  log_ok "Hermes 已安装"
  hermes --version
else
  curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash
  log_ok "Hermes 安装完成"
fi

# ============================================================
# 5. 配置 OpenClaw
# ============================================================
log_info "配置 OpenClaw..."
python3 -c "
import json
cfg = {
    \"gateway\": {\"mode\": \"local\", \"bind\": \"lan\"},
    \"agents\": {\"defaults\": {\"model\": {\"primary\": \"${PROVIDER_ID}/${MODEL_NAME}\"}}},
    \"models\": {
        \"providers\": {
            \"${PROVIDER_ID}\": {
                \"baseUrl\": \"https://coding.dashscope.aliyuncs.com/v1\",
                \"apiKey\": \"${API_KEY}\",
                \"api\": \"openai-completions\",
                \"models\": [{\"id\": \"${MODEL_NAME}\", \"name\": \"${MODEL_NAME}\", \"contextWindow\": ${CONTEXT_WINDOW}, \"maxTokens\": 8192}]
            }
        }
    },
    \"channels\": {
        \"telegram\": {
            \"enabled\": true,
            \"botToken\": \"${OPENCLAW_BOT_TOKEN}\",
            \"dmPolicy\": \"open\",
            \"allowFrom\": [\"*\"]
        }
    }
}
with open(\"/root/.openclaw/openclaw.json\", \"w\") as f:
    json.dump(cfg, f, indent=2)
"
log_ok "OpenClaw 配置完成"

# 运行 doctor 检查
log_info "运行 openclaw doctor --fix..."
export OPENCLAW_SERVICE_REPAIR_POLICY=external
openclaw doctor --fix || log_warn "doctor 检查有警告，请手动查看"

# ============================================================
# 6. 配置 Hermes
# ============================================================
log_info "配置 Hermes Agent..."
hermes config set model.provider custom
hermes config set model.default $MODEL_NAME
hermes config set model.base_url $MODEL_BASE_URL

# 配置 .env 文件
if [ "$MODE_CHOICE" = "2" ]; then
  # 模式2：独立Bot
  if grep -q 'TELEGRAM_BOT_TOKEN' /root/.hermes/.env 2>/dev/null; then
    sed -i "s/^TELEGRAM_BOT_TOKEN=.*/TELEGRAM_BOT_TOKEN=${HERMES_BOT_TOKEN}/" /root/.hermes/.env
  else
    echo "TELEGRAM_BOT_TOKEN=${HERMES_BOT_TOKEN}" >> /root/.hermes/.env
  fi
  log_ok "Hermes 独立Bot模式已配置"
else
  # 模式1：CLI集成（注释掉Token避免冲突）
  sed -i 's/^TELEGRAM_BOT_TOKEN=/# TELEGRAM_BOT_TOKEN=/' /root/.hermes/.env 2>/dev/null || true
  log_ok "Hermes CLI集成模式已配置"
fi

# ============================================================
# 7. 创建 systemd 服务
# ============================================================
log_info "创建 OpenClaw systemd 服务..."
cat > /etc/systemd/system/openclaw.service << 'EOF'
[Unit]
Description=OpenClaw Gateway
After=network.target

[Service]
Type=simple
User=root
Environment=HOME=/root
Environment=OPENCLAW_SERVICE_REPAIR_POLICY=external
ExecStart=/usr/bin/openclaw gateway --port 18789
Restart=always
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload && systemctl enable openclaw
log_ok "OpenClaw 服务已创建"

log_info "创建 Hermes systemd 服务..."
mkdir -p /root/.config/systemd/user
cat > /root/.config/systemd/user/hermes-gateway.service << 'EOF'
[Unit]
Description=Hermes Agent Gateway
After=network.target

[Service]
Type=simple
User=root
Environment=PATH=/root/.local/bin:/usr/local/bin:/usr/bin:/bin
Environment=HOME=/root
EnvironmentFile=/root/.hermes/.env
WorkingDirectory=/usr/local/lib/hermes-agent
ExecStart=/usr/local/lib/hermes-agent/venv/bin/python -m hermes_cli.main gateway run --replace
Restart=always
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=default.target
EOF
systemctl --user daemon-reload && systemctl --user enable hermes-gateway
loginctl enable-linger root
log_ok "Hermes 服务已创建"

# ============================================================
# 8. CLI集成（仅模式1）
# ============================================================
if [ "$MODE_CHOICE" = "1" ]; then
  log_info "配置 CLI 集成模式..."
  cat > /usr/local/bin/hermes-task << 'SCRIPT'
#!/bin/bash
export PATH="/root/.local/bin:/usr/local/bin:$PATH"
exec /usr/local/bin/hermes chat -q "$1" 2>/dev/null
SCRIPT
  chmod +x /usr/local/bin/hermes-task

  mkdir -p /root/.openclaw/workspace
  cat > /root/.openclaw/workspace/AGENTS.md << 'MD'
# Integration Guide
遇到复杂任务（写代码、深度分析、数据处理），通过 shell 调用 Hermes：
```bash
hermes-task "详细的任务描述"
```
Hermes 有完整的系统访问权限：Python、Node.js、shell、浏览器、文件工具。
MD
  log_ok "CLI集成已配置完成"
fi

# ============================================================
# 9. 启动服务
# ============================================================
log_info "启动服务..."
systemctl restart openclaw || true
systemctl --user restart hermes-gateway || true
log_ok "服务已启动"

# ============================================================
# 10. 验证
# ============================================================
echo ""
echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}  验证部署状态                      ${NC}"
echo -e "${BLUE}======================================${NC}"
echo ""

# 等待服务启动
sleep 3

log_info "检查 OpenClaw..."
if curl -sf http://127.0.0.1:18789/healthz >/dev/null 2>&1; then
  log_ok "OpenClaw 健康检查通过"
else
  log_warn "OpenClaw 健康检查未响应，查看日志: journalctl -u openclaw -n 20"
fi

log_info "检查 Hermes..."
if systemctl --user is-active hermes-gateway >/dev/null 2>&1; then
  log_ok "Hermes 服务运行中"
else
  log_warn "Hermes 服务未运行，查看日志: journalctl --user -u hermes-gateway -n 20"
fi

echo ""
echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}  部署完成！                        ${NC}"
echo -e "${GREEN}======================================${NC}"
echo ""
echo "模式:   $([ "$MODE_CHOICE" = "1" ] && echo "CLI集成模式" || echo "独立Bot模式")"
echo ""
echo "常用命令："
echo "  查看OpenClaw日志:   journalctl -u openclaw -f"
echo "  查看Hermes日志:     journalctl --user -u hermes-gateway -f"
echo "  重启OpenClaw:       systemctl restart openclaw"
echo "  重启Hermes:         systemctl --user restart hermes-gateway"
echo ""
