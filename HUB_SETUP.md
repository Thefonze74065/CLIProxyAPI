# CLIProxyAPI Hub Setup

This directory contains the setup for running CLIProxyAPI as a **hub** that shares
Claude and Codex auth across multiple machines, following the pattern from
[t3dotgg's gist](https://gist.github.com/t3dotgg/59a521d2ee8d70aaf90e280c175072af).

## Overview

- **Hub machine** (one computer that stays on at home): runs CLIProxyAPI on port 8317,
  signs in to all your Claude and Codex accounts, and exposes a single API endpoint.
- **Client machines** (all your other computers): point Claude Code, Codex, and T3 Code
  at the hub over [Tailscale](https://tailscale.com/).
- **Tailscale** provides secure networking — only machines on your tailnet can reach the hub.

> **Warning:** Sharing accounts across machines carries some risk of account bans.
> Theo has never had an account banned doing this, but there's always a risk.
> Don't sign in on a VPS or cloud host.

## Files in this directory

| File | Purpose |
|------|---------|
| `config.yaml` | CLIProxyAPI server configuration (port 8317, access keys, management key) |
| `.env` | Environment variables (optional remote storage, etc.) |
| `scripts/setup-hub.sh` | Interactive hub setup script |
| `scripts/setup-client.sh` | Client setup script (point machines at the hub) |
| `cli-proxy-api` | Built server binary (created by the build step) |

## Prerequisites (ask your user first)

1. **Which machine is the hub?** It must stay on, at home. Not a VPS. Not behind a VPN
   (Tailscale is fine, you need it).
2. **What's the hub's OS?**
3. **Is Tailscale on the hub and on every client, all on the same tailnet?**
4. **Which Claude and Codex accounts should sign in?** (They'll do the browser logins.)
5. **Which machines should use the hub?**
6. **Point their normal Claude Code and Codex configs at the hub**, or use a second config dir?
7. **Do they use T3 Code?** On which machines?
8. **Do they accept the ban risk?** If not, stop.

## Step 1: Hub environment checks

Run on the hub:

```bash
# OS
uname -a

# Datacenter check — if the org is a cloud host, STOP
curl -s https://ipinfo.io/org

# Port 8317 free
ss -ltn | grep 8317   # Linux
# or
lsof -iTCP:8317 -sTCP:LISTEN   # macOS

# Existing install
ls ~/cliproxyapi ~/.cli-proxy-api
systemctl --user status cliproxyapi

# Linger (Linux)
loginctl show-user "$USER" -p Linger
```

## Step 2: Build and install on the hub

```bash
cd /path/to/CLIProxyAPI

# Build the binary
go build -o cli-proxy-api ./cmd/server

# Copy to hub directory
mkdir -p ~/cliproxyapi
cp cli-proxy-api ~/cliproxyapi/
cp config.yaml ~/cliproxyapi/
cp .env ~/cliproxyapi/
```

Edit `~/cliproxyapi/config.yaml` and set:
- `access.api-keys` — your client access keys (one per client machine or shared)
- `management.secret-key` — a strong management key for the management API

## Step 3: Run as a systemd service (Linux)

```bash
mkdir -p ~/.config/systemd/user

cat > ~/.config/systemd/user/cliproxyapi.service <<'EOF'
[Unit]
Description=CLIProxyAPI Hub (Claude + Codex proxy)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$HOME/cliproxyapi
ExecStart=$HOME/cliproxyapi/cli-proxy-api -config $HOME/cliproxyapi/config.yaml
Restart=unless-stopped
RestartSec=5
Environment=HOME=$HOME

[Install]
WantedBy=default.target
EOF

# Enable linger so it survives logout
loginctl enable-linger "$(whoami)"

# Start the service
systemctl --user daemon-reload
systemctl --user enable cliproxyapi.service
systemctl --user start cliproxyapi.service

# Check status
systemctl --user status cliproxyapi
```

Or use the automated setup script:

```bash
bash scripts/setup-hub.sh
```

## Step 4: Tailscale (expose hub on the tailnet)

Install Tailscale on the hub and every client, all on the same tailnet.

On the hub:

```bash
tailscale up
tailscale serve --bg --https=8317 http://127.0.0.1:8317
```

Your hub is now at:

```
https://<hostname>.<tailnet>.ts.net:8317
```

Only machines on your tailnet can reach it.

> **Mac client DNS fix:** If a Mac client can't resolve `*.ts.net` with open-source `tailscaled`:
> ```bash
> sudo mkdir -p /etc/resolver
> echo "nameserver 100.100.100.100" | sudo tee /etc/resolver/<tailnet>.ts.net
> ```

## Step 5: Sign in to Claude and Codex accounts

On the hub, run the OAuth / device login flows:

```bash
cd ~/cliproxyapi

# Claude OAuth login
./cli-proxy-api -claude-login

# Codex device login
./cli-proxy-api -codex-device-login
```

Or open the management UI at:

```
http://127.0.0.1:8317/management.html
```

or via Tailscale:

```
https://<hostname>.<tailnet>.ts.net:8317/management.html
```

Auth material is stored under `~/.cli-proxy-api/` (the `auths/` directory).

## Step 6: Point clients at the hub

### Claude Code (`~/.claude/settings.json` on each client)

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "https://<hostname>.<tailnet>.ts.net:8317",
    "ANTHROPIC_AUTH_TOKEN": "<your access key>"
  }
}
```

### Codex (`~/.codex/config.toml` on each client)

```toml
model_provider = "cliproxy"

[model_providers.cliproxy]
name = "CLIProxyAPI"
base_url = "https://<hostname>.<tailnet>.ts.net:8317/v1"
wire_api = "responses"
requires_openai_auth = false
supports_websockets = true
experimental_bearer_token = "<your access key>"
```

Or use the client setup script:

```bash
HUB_URL=https://<hostname>.<tailnet>.ts.net:8317 \
ACCESS_KEY=<your access key> \
bash scripts/setup-client.sh
```

### T3 Code

T3 Code runs providers on the environment's machine, using that machine's CLI config.
If Claude Code on that machine points at the hub, Claude in T3 Code does too.

For Codex, pick **Use existing CLI** (reads `config.toml`). **Continue with ChatGPT**
won't go through the hub.

For pooled limits in T3 Code: Settings > Providers > Usage providers > Add hub.

## Things to verify

1. **Session affinity:** Caches are account-specific. If a thread hops accounts per prompt,
   you waste cache writes. Check your cache read/write numbers.
2. **Codex over websockets:** Make sure `supports_websockets = true` in the Codex config.
3. **Management UI:** Visit `https://<hostname>.<tailnet>.ts.net:8317/management.html`
   to confirm accounts are registered.

## When stuff breaks

| Problem | Fix |
|---------|-----|
| Need to bench an account? | Set `"disabled": true` in its auth JSON in `~/.cli-proxy-api`. Drops out of rotation with no restart. |
| Codex `token_invalidated` (401)? | Rerun device login on the hub: `./cli-proxy-api -codex-device-login` |
| Only one account enabled? | A limit hit has nowhere else to go. Add a second account. |
| Mac can't resolve `*.ts.net`? | See the Mac client DNS fix above. |

## Alternative: Deploy as Docker on TrueNAS (Dockge)

CI automatically builds and publishes multi-arch Docker images to [Docker Hub](https://hub.docker.com/r/eceasy/cli-proxy-api) (`eceasy/cli-proxy-api:latest`) whenever a version tag is pushed. You don't need to build anything locally — just pull the image and run it.

### Files for Docker deployment

| File | Purpose |
|------|---------|
| `docker-compose.dockge.yml` | Docker Compose for Dockge stack (pulls `eceasy/cli-proxy-api:latest`) |
| `.env.dockge` | Environment variables (copy to `.env`) |
| `config.dockge.yaml` | Server config (copy to `config.yaml`) |

### Deployment steps

1. **Create the stack directory on TrueNAS:**
   ```bash
   mkdir -p /mnt/<pool>/apps/cliproxyapi
   cd /mnt/<pool>/apps/cliproxyapi
   ```

2. **Copy the Docker files:**
   ```bash
   cp /path/to/CLIProxyAPI/docker-compose.dockge.yml ./docker-compose.yml
   cp /path/to/CLIProxyAPI/.env.dockge ./.env
   cp /path/to/CLIProxyAPI/config.dockge.yaml ./config.yaml
   ```

3. **Customize the configuration:**
   - Edit `.env` — set `MANAGEMENT_PASSWORD` to a strong password
   - Edit `config.yaml` — set `access.api-keys` (your client access keys) and `management.secret-key` (management API key)

4. **Create the data directories:**
   ```bash
   mkdir -p auths logs plugins
   ```

5. **Deploy via Dockge:**
   - In Dockge, create a new stack pointing at `/mnt/<pool>/apps/cliproxyapi`
   - Deploy the stack — Dockge will pull `eceasy/cli-proxy-api:latest` automatically

6. **Access the management UI:**
   ```
   http://<truenas-ip>:8317/management.html
   ```
   Or via Tailscale:
   ```
   https://<hostname>.<tailnet>.ts.net:8317/management.html
   ```

7. **Sign in to Claude and Codex:**
   ```bash
   # From the TrueNAS host, exec into the running container:
   docker exec -it cli-proxy-api ./cli-proxy-api -claude-login
   docker exec -it cli-proxy-api ./cli-proxy-api -codex-device-login
   ```

### Tailscale on TrueNAS

Install Tailscale on TrueNAS (via a Tailscale container or the TrueNAS Tailscale plugin), then run:

```bash
tailscale up
tailscale serve --bg --https=8317 http://<truenas-ip>:8317
```

Your hub will be at `https://<hostname>.<tailnet>.ts.net:8317`.

---

Now go burn your tokens before they reset 💀