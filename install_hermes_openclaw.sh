#!/usr/bin/env bash
# 安装 OpenClaw + Hermes Agent

# 安装 OpenClaw（跳过交互配置）
curl -fsSL https://openclaw.ai/install.sh | bash -s -- --no-prompt --no-onboard

# 安装 Hermes Agent（跳过初始配置和浏览器安装）
curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash -s -- --skip-setup --skip-browser
