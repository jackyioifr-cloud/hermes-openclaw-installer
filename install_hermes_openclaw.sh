#!/usr/bin/env bash
# 安装 Hermes Agent + OpenClaw

# 安装 Hermes Agent（跳过初始配置和浏览器安装）
curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash -s -- --skip-setup --skip-browser

# 安装 OpenClaw
curl -fsSL https://openclaw.ai/install.sh | bash
