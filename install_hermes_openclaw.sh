#!/usr/bin/env bash
# Install Hermes Agent + OpenClaw

curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash -s -- --skip-setup --skip-browser
curl -fsSL https://openclaw.ai/install.sh | bash
