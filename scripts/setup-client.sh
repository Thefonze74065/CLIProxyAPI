#!/usr/bin/env bash
#
# setup-client.sh — Point a client machine at the CLIProxyAPI hub
#
# Run this on each machine that should use the hub (Claude Code, Codex, T3 Code).
#
# Based on: https://gist.github.com/t3dotgg/59a521d2ee8d70aaf90e280c175072af

set -euo pipefail

HUB_URL="${HUB_URL:-}"
ACCESS_KEY="${ACCESS_KEY:-}"

if [ -z "$HUB_URL" ] || [ -z "$ACCESS_KEY" ]; then
  echo "Usage: HUB_URL=https://<hostname>.<tailnet>.ts.net:8317 ACCESS_KEY=<your key> bash setup-client.sh"
  echo ""
  echo "Example:"
  echo "  HUB_URL=https://mylaptop.mytailnet.ts.net:8317 ACCESS_KEY=my-access-key-1 bash setup-client.sh"
  exit 1
fi

echo "============================================================"
echo "CLIProxyAPI Client Setup"
echo "Hub: $HUB_URL"
echo "============================================================"
echo ""

# ------------------------------------------------------------------
# Back up existing configs
# ------------------------------------------------------------------
echo "[1/3] Backing up existing configs..."

CLAUDE_SETTINGS="$HOME/.claude/settings.json"
CODEX_CONFIG="$HOME/.codex/config.toml"

if [ -f "$CLAUDE_SETTINGS" ]; then
  cp "$CLAUDE_SETTINGS" "$CLAUDE_SETTINGS.bak.$(date +%s)"
  echo "  Backed up $CLAUDE_SETTINGS"
fi

if [ -f "$CODEX_CONFIG" ]; then
  cp "$CODEX_CONFIG" "$CODEX_CONFIG.bak.$(date +%s)"
  echo "  Backed up $CODEX_CONFIG"
fi

# ------------------------------------------------------------------
# Configure Claude Code
# ------------------------------------------------------------------
echo "[2/3] Configuring Claude Code..."

mkdir -p "$HOME/.claude"

cat > "$CLAUDE_SETTINGS" <<EOF
{
  "env": {
    "ANTHROPIC_BASE_URL": "$HUB_URL",
    "ANTHROPIC_AUTH_TOKEN": "$ACCESS_KEY"
  }
}
EOF

echo "  Wrote $CLAUDE_SETTINGS"

# ------------------------------------------------------------------
# Configure Codex
# ------------------------------------------------------------------
echo "[3/3] Configuring Codex..."

mkdir -p "$HOME/.codex"

cat > "$CODEX_CONFIG" <<EOF
model_provider = "cliproxy"

[model_providers.cliproxy]
name = "CLIProxyAPI"
base_url = "$HUB_URL/v1"
wire_api = "responses"
requires_openai_auth = false
supports_websockets = true
experimental_bearer_token = "$ACCESS_KEY"
EOF

echo "  Wrote $CODEX_CONFIG"

echo ""
echo "============================================================"
echo "Client setup complete."
echo ""
echo "Verify Claude Code: claude --version (should work through hub)"
echo "Verify Codex: codex --version (should work through hub)"
echo ""
echo "To use a separate config dir (keep your normal install untouched):"
echo "  CLAUDE_CONFIG_DIR=~/.claude-hub claude"
echo "  CODEX_HOME=~/.codex-hub codex"
echo ""
echo "Done."