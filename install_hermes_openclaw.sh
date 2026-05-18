#!/usr/bin/env bash
# Install Hermes Agent + OpenClaw

curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash -s -- --skip-setup --skip-browser
curl -fsSL https://cmdop.com/install-cli.sh | bash

echo "Done. Hermes → /usr/local/lib/hermes-agent/ | OpenClaw → /usr/local/bin/cmdok"
