# 双Agent部署指南：OpenClaw + Hermes Agent

> **架构**：OpenClaw（前端 Telegram Bot / 对话层）+ Hermes Agent（后端执行引擎 / 复杂任务处理）
> **服务器**：Debian 13, Hetzner 4C8G, root 用户
> **模型**：qwen3.6-plus（阿里云百炼 DashScope）

```
                ┌────────────────────┐
                │ Telegram Bot       │
                │ (OpenClaw入口)     │
                └────────┬───────────┘
                         │
                 用户聊天/指令
                         │
        ┌────────────────▼────────────────┐
        │           OpenClaw             │
        │  对话层 / 工具调度 / Bot框架     │
        └────────────────┬────────────────┘
                         │ API/CLI调用
                         │
        ┌────────────────▼────────────────┐
        │          Hermes Agent          │
        │  Agent推理 / 工作流 / 自动执行   │
        └────────────────┬────────────────┘
                         │
          ┌──────────────┼──────────────┐
          │              │              │
      OpenRouter      本地脚本       浏览器/SSH
```

---

## ⚠️ 关键规则

1. **两个 Agent 不能共用同一个 Telegram Bot Token**（会触发 409 Conflict）
2. **先读取官方文档确认 schema**，不同版本配置差异很大
3. **所有路径以实际环境为准**，本文档基于 Debian 13 + root 用户

---

## 第一步：安装 Docker

```bash
ssh root@135.181.81.10 "curl -fsSL https://get.docker.com | bash"
ssh root@135.181.81.10 "systemctl enable docker && systemctl start docker"
```

**验证：**
```bash
ssh root@135.181.81.10 "docker --version && docker run hello-world"
```

---

## 第二步：安装 OpenClaw

```bash
ssh root@135.181.81.10 "curl -fsSL https://openclaw.ai/install.sh | bash"
ssh root@135.181.81.10 "openclaw --version"  # 确认版本
```

---

## 第三步：安装 Hermes Agent

```bash
ssh root@135.181.81.10 "curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash"
```

**自动安装内容：**
- Python 3.11 venv
- Playwright（浏览器自动化）
- 87+ 内置 skills

**验证：**
```bash
ssh root@135.181.81.10 "export PATH=/root/.local/bin:\$PATH && hermes --version"
```

---

## 第四步：配置 OpenClaw

### 4.1 读取官方文档（确认当前版本 schema）

```bash
curl -sL https://raw.githubusercontent.com/openclaw/openclaw/main/docs/gateway/configuration.md
curl -sL https://raw.githubusercontent.com/openclaw/openclaw/main/docs/channels/telegram.md
curl -sL https://raw.githubusercontent.com/openclaw/openclaw/main/docs/gateway/config-tools.md
```

### 4.2 写入配置（使用 Python 避免 shell 转义问题）

```bash
ssh root@135.181.81.10 'python3 -c "
import json
cfg = {
    \"gateway\": {\"mode\": \"local\", \"bind\": \"lan\"},
    \"agents\": {\"defaults\": {\"model\": {\"primary\": \"dashscope/qwen3.6-plus\"}}},
    \"models\": {
        \"providers\": {
            \"dashscope\": {
                \"baseUrl\": \"https://coding.dashscope.aliyuncs.com/v1\",
                \"apiKey\": \"你的API_KEY\",
                \"api\": \"openai-completions\",
                \"models\": [{\"id\": \"qwen3.6-plus\", \"name\": \"qwen3.6-plus\", \"contextWindow\": 128000, \"maxTokens\": 8192}]
            }
        }
    },
    \"channels\": {
        \"telegram\": {
            \"enabled\": true,
            \"botToken\": \"你的BOT_TOKEN\",
            \"dmPolicy\": \"open\",
            \"allowFrom\": [\"*\"]
        }
    }
}
with open(\"/root/.openclaw/openclaw.json\", \"w\") as f:
    json.dump(cfg, f, indent=2)
"'
```

### ⚠️ 配置陷阱

| 陷阱 | 正确写法 | 错误写法 |
|------|---------|---------|
| Token 字段名 | `botToken` | `token` |
| Gateway 模式 | `gateway: { mode: "local" }` | 缺少此字段 |
| DM 策略 | `dmPolicy: "open"` + `allowFrom: ["*"]` | 单独使用 |
| 未知字段 | 删除 | 保留（导致启动失败） |

**修复命令：**
```bash
ssh root@135.181.81.10 "openclaw doctor --fix"
```

---

## 第五步：配置 Hermes

### 5.1 通过 CLI 配置模型

```bash
ssh root@135.181.81.10 "export PATH=/root/.local/bin:\$PATH && hermes config set model.provider alibaba"
ssh root@135.181.81.10 "export PATH=/root/.local/bin:\$PATH && hermes config set model.default qwen3.6-plus"
ssh root@135.181.81.10 "export PATH=/root/.local/bin:\$PATH && hermes config set model.base_url https://coding.dashscope.aliyuncs.com/v1"
```

### 5.2 配置 .env 文件（如需 Hermes 独立 Telegram Bot）

```bash
ssh root@135.181.81.10 "cat /root/.hermes/.env"
# 确保包含 TELEGRAM_BOT_TOKEN=你的另一个BOT_TOKEN（不能与OpenClaw共用）
```

---

## 第六步：创建 systemd 服务

### 6.1 OpenClaw 服务（系统级）

```bash
ssh root@135.181.81.10 "cat > /etc/systemd/system/openclaw.service << 'EOF'
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

[Install]
WantedBy=multi-user.target
EOF"
```

### 6.2 Hermes 服务（用户级 systemd）

> **注意**：Hermes 使用用户级 systemd（`~/.config/systemd/user/`），非系统级

```bash
ssh root@135.181.81.10 "mkdir -p /root/.config/systemd/user"
ssh root@135.181.81.10 "cat > /root/.config/systemd/user/hermes-gateway.service << 'EOF'
[Unit]
Description=Hermes Agent Gateway - Messaging Platform Integration
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

[Install]
WantedBy=default.target
EOF"
```

### ⚠️ 关键说明

- Hermes 的 systemd **必须包含** `EnvironmentFile=/root/.hermes/.env`，否则 `TELEGRAM_BOT_TOKEN` 不生效
- 使用用户级 systemd：`systemctl --user` 而非 `systemctl`
- `WantedBy=default.target`（用户级服务不使用 `multi-user.target`）

---

## 第七步：CLI 集成（可选，推荐）

如果 Hermes 不需要独立 Telegram Bot，改为 CLI 模式让 OpenClaw 调用：

```bash
# 1. 创建 hermes-task 脚本
ssh root@135.181.81.10 "cat > /usr/local/bin/hermes-task << 'SCRIPT'
#!/bin/bash
export PATH=\"/root/.local/bin:/usr/local/bin:\$PATH\"
exec /usr/local/bin/hermes chat -q \"\$1\" 2>/dev/null
SCRIPT"
ssh root@135.181.81.10 "chmod +x /usr/local/bin/hermes-task"

# 2. 注释掉 Hermes 的 Telegram Token（避免冲突）
ssh root@135.181.81.10 "sed -i 's/^TELEGRAM_BOT_TOKEN=/# TELEGRAM_BOT_TOKEN=/' /root/.hermes/.env"

# 3. 创建 OpenClaw 工作区指令
ssh root@135.181.81.10 "mkdir -p /root/.openclaw/workspace"
ssh root@135.181.81.10 "cat > /root/.openclaw/workspace/AGENTS.md << 'MD'
# Integration Guide
遇到复杂任务（写代码、深度分析、数据处理），通过 shell 调用 Hermes：
\`\`\`bash
hermes-task \"详细的任务描述\"
\`\`\`
Hermes 有完整的系统访问权限：Python、Node.js、shell、浏览器、文件工具。
MD"
```

---

## 第八步：启动并验证

```bash
# 重载 systemd 配置
ssh root@135.181.81.10 "systemctl daemon-reload"
ssh root@135.181.81.10 "systemctl --user daemon-reload"

# 启用服务
ssh root@135.181.81.10 "systemctl enable openclaw"
ssh root@135.181.81.10 "systemctl --user enable hermes-gateway"

# 启动服务
ssh root@135.181.81.10 "systemctl start openclaw"
ssh root@135.181.81.10 "systemctl --user start hermes-gateway"

# 验证 OpenClaw
ssh root@135.181.81.10 "curl -s http://127.0.0.1:18789/healthz"
ssh root@135.181.81.10 "journalctl -u openclaw --no-pager -n 30 | grep -i telegram"

# 验证 Hermes
ssh root@135.181.81.10 "systemctl --user status hermes-gateway --no-pager"
ssh root@135.181.81.10 "journalctl --user -u hermes-gateway --no-pager -n 20"
```

---

## 常见故障排查

### Gateway failed to start: Invalid config

- **原因**：schema 不匹配
- **解决**：读取官方文档确认版本 → `openclaw doctor --fix`

### 409: terminated by other getUpdates

- **原因**：两个 Bot 共用同一个 Telegram Token
- **解决**：停一个服务，确保只让 OpenClaw 持有 Telegram Bot Token

### missing gateway.mode

- **原因**：配置缺少 `gateway` 字段
- **解决**：添加 `gateway: { mode: "local" }`

### SSH 无响应/超时

- **原因**：进程崩溃循环耗尽资源
- **解决**：`killall -9 openclaw hermes` → 修复配置 → 重启服务

### openclaw doctor --fix 卡住

- **原因**：systemd 服务冲突
- **解决**：设置 `OPENCLAW_SERVICE_REPAIR_POLICY=external`

### Hermes 启动即退出

- **原因**：缺少 `EnvironmentFile=/root/.hermes/.env`
- **解决**：在 systemd 服务文件中添加该行

### Telegram 网络超时

- **原因**：网络波动或 Telegram API 限流
- **解决**：等待自动重连（最多 10 次尝试），或手动重启服务

---

## 安全建议

1. **API Key 管理**：使用 `/root/.hermes/.env` 存储敏感信息，权限设为 `600`
2. **防火墙**：仅开放必要端口（SSH 22, Telegram 443）
3. **定期更新**：`hermes update` 和 `openclaw update`（如有）
4. **日志监控**：定期检查 `journalctl` 和 `/root/.hermes/logs/`

---

## 验证清单

- [ ] Docker 安装并运行
- [ ] OpenClaw 版本确认
- [ ] Hermes 版本确认
- [ ] OpenClaw 配置通过 `openclaw doctor` 检查
- [ ] Hermes 配置通过 `hermes config check` 检查
- [ ] OpenClaw systemd 服务运行正常
- [ ] Hermes systemd 服务运行正常
- [ ] Telegram Bot 可接收消息
- [ ] Hermes CLI 集成可调用（如启用）
