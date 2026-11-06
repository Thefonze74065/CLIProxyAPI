#!/usr/bin/env bash
#
# setup-hub.sh — Set up CLIProxyAPI as a Claude + Codex hub (per gist)
#
# Based on: https://gist.github.com/t3dotgg/59a521d2ee8d70aaf90e280c175072af

set -euo pipefail

HUB_DIR="$HOME/cliproxyapi"
BINARY_NAME="cli-proxy-api"
CONFIG_FILE="config.yaml"
ENV_FILE=".env"

echo "============================================================"
echo "CLIProxyAPI Hub Setup (per t3dotgg's gist)"
echo "============================================================"
echo ""

# ------------------------------------------------------------------
# Step 0: Environment checks
# ------------------------------------------------------------------
echo "[0/7] Checking environment..."
echo "  OS: $(uname -a)"

ORG=$(curl -s https://ipinfo.io/org 2>/dev/null || echo "unknown")
echo "  IP org: $ORG"
case "$ORG" in
  *Amazon*|*AWS*|*Hetzner*|*DigitalOcean*|*OVH*|*Google*|*Microsoft*|*Azure*)
    echo "  ERROR: This looks like a cloud host. Do not sign in to Claude/Codex on a VPS."
    echo "  Aborting."
    exit 1
    ;;
esac

if command -v ss >/dev/null 2>&1; then
  if ss -ltn 2>/dev/null | grep -q ':8317'; then
    echo "  ERROR: Port 8317 is already in use."
    exit 1
  fi
elif command -v lsof >/dev/null 2>&1; then
  if lsof -iTCP:8317 -sTCP:LISTEN >/dev/null 2>&1; then
    echo "  ERROR: Port 8317 is already in use."
    exit 1
  fi
fi
echo "  OK: Port 8317 is free."

if ! command -v go >/dev/null 2>&1; then
  echo "  ERROR: Go is not installed. Install Go 1.26+ first."
  exit 1
fi
echo "  Go: $(go version)"

echo ""
echo "[0/7] Environment checks passed."

# ------------------------------------------------------------------
# Step 1: Install CLIProxyAPI (build from source)
# ------------------------------------------------------------------
echo "[1/7] Installing CLIProxyAPI..."

if [ ! -d "$HUB_DIR" ]; then
  echo "  Creating $HUB_DIR ..."
  mkdir -p "$HUB_DIR"
fi

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ ! -f "$REPO_DIR/$BINARY_NAME" ]; then
  echo "  Building $BINARY_NAME from source..."
  (cd "$REPO_DIR" && go build -o "$BINARY_NAME" ./cmd/server)
fi

cp "$REPO_DIR/$BINARY_NAME" "$HUB_DIR/$BINARY_NAME"
chmod +x "$HUB_DIR/$BINARY_NAME"
echo "  Binary installed at $HUB_DIR/$BINARY_NAME"

# ------------------------------------------------------------------
# Step 2: Create config.yaml and .env
# ------------------------------------------------------------------
echo "[2/7] Writing configuration..."

if [ ! -f "$HUB_DIR/$CONFIG_FILE" ]; then
  cp "$REPO_DIR/config.yaml" "$HUB_DIR/$CONFIG_FILE"
  echo "  Created $HUB_DIR/$CONFIG_FILE"
else
  echo "  $HUB_DIR/$CONFIG_FILE already exists, skipping."
fi

if [ ! -f "$HUB_DIR/$ENV_FILE" ]; then
  cp "$REPO_DIR/.env" "$HUB_DIR/$ENV_FILE"
  echo "  Created $HUB_DIR/$ENV_FILE"
else
  echo "  $HUB_DIR/$ENV_FILE already exists, skipping."
fi

echo ""
echo "  IMPORTANT: Edit $HUB_DIR/$CONFIG_FILE and set:"
echo "    - access.api-keys: your client access keys (Claude Code, Codex, T3 Code)"
echo "    - management.secret-key: a strong management key"
echo ""

# ------------------------------------------------------------------
# Step 3: Create systemd user service
# ------------------------------------------------------------------
echo "[3/7] Setting up systemd user service..."

SERVICE_DIR="$HOME/.config/systemd/user"
mkdir -p "$SERVICE_DIR"

cat > "$SERVICE_DIR/cliproxyapi.service" <<EOF
[Unit]
Description=CLIProxyAPI Hub (Claude + Codex proxy)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$HUB_DIR
ExecStart=$HUB_DIR/$BINARY_NAME -config $HUB_DIR/$CONFIG_FILE
Restart=unless-stopped
RestartSec=5
Environment=HOME=$HOME

[Install]
WantedBy=default.target
EOF

echo "  Service file created at $SERVICE_DIR/cliproxyapi.service"

# ------------------------------------------------------------------
# Step 4: Enable linger (so the service runs without a login session)
# ------------------------------------------------------------------
echo "[4/7] Enabling user linger..."
if command -v loginctl >/dev/null 2>&1; then
  loginctl enable-linger "$(whoami)" 2>/dev/null || true
  echo "  Linger enabled for $(whoami)"
else
  echo "  loginctl not found; skipping linger (service may not survive logout)."
fi

# ------------------------------------------------------------------
# Step 5: Start the service
# ------------------------------------------------------------------
echo "[5/7] Starting CLIProxyAPI service..."
if command -v systemctl >/dev/null 2>&1; then
  systemctl --user daemon-reload
  systemctl --user enable cliproxyapi.service
  systemctl --user start cliproxyapi.service
  echo "  Service started. Check status with: systemctl --user status cliproxyapi"
else
  echo "  systemctl not found; start manually with:"
  echo "    cd $HUB_DIR && ./$BINARY_NAME -config $HUB_DIR/$CONFIG_FILE"
fi

# ------------------------------------------------------------------
# Step 6: Tailscale serve
# ------------------------------------------------------------------
echo "[6/7] Tailscale setup..."
if command -v tailscale >/dev/null 2>&1; then
  echo "  Tailscale is installed."
  echo ""
  echo "  Run these commands on the hub:"
  echo "    tailscale up"
  echo "    tailscale serve --bg --https=8317 http://127.0.0.1:8317"
  echo ""
  echo "  Your hub will be at: https://<hostname>.<tailnet>.ts.net:8317"
else
  echo "  Tailscale is NOT installed."
  echo ""
  echo "  Install Tailscale on the hub and on every client, then run:"
  echo "    tailscale up"
  echo "    tailscale serve --bg --https=8317 http://127.0.0.1:8317"
fi

# ------------------------------------------------------------------
# Step 7: Sign in to Claude and Codex accounts
# ------------------------------------------------------------------
echo "[7/7] Account sign-in..."
echo ""
echo "  Sign in to your Claude and Codex accounts on the hub:"
echo "    $HUB_DIR/$BINARY_NAME -claude-login"
echo "    $HUB_DIR/$BINARY_NAME -codex-device-login"
echo ""
echo "  Or use the management UI at http://127.0.0.1:8317/management.html"
echo "  (or via Tailscale at https://<hostname>.<tailnet>.ts.net:8317/management.html)"

echo ""
echo "============================================================"
echo "Hub setup complete. Next: point your clients at the hub."
echo "============================================================"
echo ""
echo "Claude Code — in ~/.claude/settings.json on each client:"
echo '  {'
echo '    "env": {'
echo "      \"ANTHROPIC_BASE_URL\": \"https://<hostname>.<tailnet>.ts.net:8317\","
echo '      "ANTHROPIC_AUTH_TOKEN": "<your access key>"'
echo '    }'
echo '  }'
echo ""
echo "Codex — in ~/.codex/config.toml on each client:"
echo '  model_provider = "cliproxy"'
echo ""
echo '  [model_providers.cliproxy]'
echo '  name = "CLIProxyAPI"'
echo '  base_url = "https://<hostname>.<tailnet>.ts.net:8317/v1"'
echo '  wire_api = "responses"'
echo '  requires_openai_auth = false'
echo '  supports_websockets = true'
echo '  experimental_bearer_token = "<your access key>"'
echo ""
echo "Done. Burn your tokens before they reset 💀"