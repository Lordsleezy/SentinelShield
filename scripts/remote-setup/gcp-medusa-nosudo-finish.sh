#!/usr/bin/env bash
set -euo pipefail

USER_NAME="$(whoami)"
HOME_DIR="$HOME"
MEDUSA_ROOT="/opt/medusa"
DB_URL="postgresql://sentinel:maddy123@localhost:5432/sentinel_market"
REPORT="/tmp/gcp-medusa-final-report.txt"
BIN_DIR="$HOME_DIR/bin"

log() { echo ">>> $*"; }
report() { echo "$*" | tee -a "$REPORT"; }

export NVM_DIR="$HOME_DIR/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
nvm use 20 >/dev/null

mkdir -p "$BIN_DIR" "$HOME_DIR/.config/systemd/user" "$MEDUSA_ROOT/logs"
loginctl enable-linger "$USER_NAME" 2>/dev/null || true

: > "$REPORT"
report "========================================"
report "   GCP MEDUSA SETUP FINAL REPORT"
report "   $(date)"
report "========================================"

# --- Medusa install ---
if [ ! -f "$MEDUSA_ROOT/package.json" ] && [ ! -f "$MEDUSA_ROOT/apps/backend/package.json" ]; then
  log "Creating Medusa app..."
  BUILD_DIR="$HOME_DIR/medusa-build"
  rm -rf "$BUILD_DIR"
  cd "$HOME_DIR"
  printf 'N\n' | npx --yes create-medusa-app@latest medusa-build \
    --db-url "$DB_URL" \
    --no-browser \
    --use-npm 2>&1 | tee /tmp/medusa-create.log | tail -80
  rm -rf "$MEDUSA_ROOT"
  mkdir -p "$MEDUSA_ROOT"
  shopt -s dotglob
  mv "$BUILD_DIR"/* "$MEDUSA_ROOT"/
  shopt -u dotglob
  rm -rf "$BUILD_DIR"
fi

if [ -f "$MEDUSA_ROOT/apps/backend/package.json" ]; then
  MEDUSA_DIR="$MEDUSA_ROOT/apps/backend"
elif [ -f "$MEDUSA_ROOT/package.json" ]; then
  MEDUSA_DIR="$MEDUSA_ROOT"
else
  report "ERROR: Medusa install failed"
  tail -20 /tmp/medusa-create.log 2>/dev/null | tee -a "$REPORT"
  exit 1
fi

cd "$MEDUSA_DIR"
cat > .env << ENVEOF
DATABASE_URL=$DB_URL
STORE_CORS=http://localhost:8000,https://legion.sentinelprime.org,https://market.sentinelprime.org
ADMIN_CORS=http://localhost:7001,http://localhost:9000,https://legion.sentinelprime.org
AUTH_CORS=http://localhost:7001,http://localhost:9000,https://legion.sentinelprime.org
REDIS_URL=redis://localhost:6379
JWT_SECRET=$(openssl rand -hex 32)
COOKIE_SECRET=$(openssl rand -hex 32)
PORT=9000
MEDUSA_API_URL=http://localhost:9000
MEDUSA_API_KEY=
ENVEOF

if [ "$MEDUSA_DIR" != "$MEDUSA_ROOT" ]; then
  cd "$MEDUSA_ROOT" && npm install 2>&1 | tail -5
  cd "$MEDUSA_DIR"
fi

log "Migrations..."
npx medusa db:migrate 2>&1 | tail -15

log "Admin user..."
npx medusa user --email admin@sentinelprime.org --password maddy123 2>&1 || true

MEDUSA_VER=$(node -e "const p=require('$MEDUSA_ROOT/package.json'); console.log(p.dependencies?.['@medusajs/medusa']||'installed')" 2>/dev/null)

NODE_PATH=$(dirname "$(which node)")
NPX_BIN=$(which npx)

# User systemd for Medusa
cat > "$HOME_DIR/.config/systemd/user/sentinel-medusa.service" << SVCEOF
[Unit]
Description=Sentinel Medusa v2 Store
After=network.target

[Service]
Type=simple
WorkingDirectory=$MEDUSA_DIR
EnvironmentFile=$MEDUSA_DIR/.env
Environment=PATH=$NODE_PATH:/usr/local/bin:/usr/bin:/bin
Environment=NODE_ENV=development
ExecStart=$NPX_BIN medusa develop
Restart=on-failure
RestartSec=10
StandardOutput=append:$MEDUSA_ROOT/logs/medusa.log
StandardError=append:$MEDUSA_ROOT/logs/medusa.log

[Install]
WantedBy=default.target
SVCEOF

systemctl --user daemon-reload
systemctl --user enable sentinel-medusa
systemctl --user restart sentinel-medusa

MEDUSA_OK=false
for i in $(seq 1 60); do
  curl -sf http://localhost:9000/health >/dev/null 2>&1 && MEDUSA_OK=true && break
  sleep 5
done

# API key
MEDUSA_API_KEY=""
if [ "$MEDUSA_OK" = true ]; then
  TOKEN=$(curl -sf -X POST "http://localhost:9000/auth/user/emailpass" \
    -H "Content-Type: application/json" \
    -d '{"email":"admin@sentinelprime.org","password":"maddy123"}' | \
    python3 -c "import sys,json; print(json.load(sys.stdin).get('token',''))" 2>/dev/null || echo "")
  if [ -n "$TOKEN" ]; then
    MEDUSA_API_KEY=$(curl -sf -X POST "http://localhost:9000/admin/api-keys" \
      -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/json" \
      -d '{"title":"Sentinel Server Key","type":"secret"}' | \
      python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('api_key',d).get('token',''))" 2>/dev/null || echo "")
  fi
  if [ -n "$MEDUSA_API_KEY" ]; then
    sed -i "s|^MEDUSA_API_KEY=.*|MEDUSA_API_KEY=$MEDUSA_API_KEY|" "$MEDUSA_DIR/.env"
  fi
fi

# Cloudflared
CF_BIN="$BIN_DIR/cloudflared"
if [ ! -x "$CF_BIN" ]; then
  curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64" -o "$CF_BIN"
  chmod +x "$CF_BIN"
fi

mkdir -p "$HOME_DIR/.cloudflared"
TUNNEL_READY=false
TUNNEL_ID=""
CF_AUTH=false

if "$CF_BIN" tunnel list 2>/dev/null | grep -q "sentinel-cloud"; then
  TUNNEL_ID=$("$CF_BIN" tunnel list 2>/dev/null | awk '/sentinel-cloud/ {print $1; exit}')
  TUNNEL_READY=true
  CF_AUTH=true
else
  CREATE_OUT=$("$CF_BIN" tunnel create sentinel-cloud 2>&1 || true)
  if echo "$CREATE_OUT" | grep -qE '[0-9a-f-]{36}'; then
    TUNNEL_ID=$(echo "$CREATE_OUT" | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | head -1)
    TUNNEL_READY=true
    CF_AUTH=true
  elif echo "$CREATE_OUT" | grep -qi "login\|authorize\|certificate"; then
    CF_AUTH=false
  fi
fi

if [ "$TUNNEL_READY" = true ] && [ -n "$TUNNEL_ID" ]; then
  CONFIG="$HOME_DIR/.cloudflared/config.yml"
  cat > "$CONFIG" << CFEOF
tunnel: $TUNNEL_ID
credentials-file: $HOME_DIR/.cloudflared/${TUNNEL_ID}.json

ingress:
  - hostname: legion.sentinelprime.org
    service: http://localhost:9000
  - service: http_status:404
CFEOF

  cat > "$HOME_DIR/.config/systemd/user/sentinel-cloudflared.service" << CFUNIT
[Unit]
Description=Sentinel Cloudflare Tunnel
After=network.target sentinel-medusa.service

[Service]
ExecStart=$CF_BIN tunnel --config $CONFIG run
Restart=on-failure
RestartSec=10
StandardOutput=append:$MEDUSA_ROOT/logs/cloudflared.log
StandardError=append:$MEDUSA_ROOT/logs/cloudflared.log

[Install]
WantedBy=default.target
CFUNIT

  systemctl --user daemon-reload
  systemctl --user enable sentinel-cloudflared
  systemctl --user restart sentinel-cloudflared || true
fi

# --- Report ---
report ""
report "--- PostgreSQL ---"
report "Version: $(psql --version)"
report "Service: $(systemctl is-active postgresql) / $(systemctl is-enabled postgresql)"
report "Database: sentinel_market (user: sentinel)"

report ""
report "--- Medusa ---"
report "Version: $MEDUSA_VER"
report "Install path: $MEDUSA_DIR"
report "Service: $(systemctl --user is-active sentinel-medusa) (user systemd)"
report "Health: $(curl -sf http://localhost:9000/health && echo OK || echo FAILED)"
report "Admin panel: http://136.118.148.167:9000/app"
report "Admin login: admin@sentinelprime.org / maddy123"
report "Public URL: https://legion.sentinelprime.org/app (after tunnel DNS)"

report ""
report "--- API Key ---"
if [ -n "$MEDUSA_API_KEY" ]; then
  report "Generated: ${MEDUSA_API_KEY:0:12}...${MEDUSA_API_KEY: -4}"
  report "Saved: $MEDUSA_DIR/.env"
else
  report "Not generated — create via admin panel after Medusa is healthy"
fi

report ""
report "--- UFW ---"
report "SKIPPED: pgg124 has no sudo access"
report "Configure GCP VPC firewall instead: allow tcp 22, 80, 443, 9000"

report ""
report "--- Cloudflare Tunnel ---"
report "cloudflared: $($CF_BIN --version 2>&1 | head -1)"
if [ "$TUNNEL_READY" = true ]; then
  report "Tunnel: sentinel-cloud ($TUNNEL_ID)"
  report "Route: legion.sentinelprime.org -> http://localhost:9000"
  report "Service: $(systemctl --user is-active sentinel-cloudflared 2>/dev/null || echo inactive)"
  report "DNS: CNAME legion.sentinelprime.org -> ${TUNNEL_ID}.cfargotunnel.com"
else
  report "MANUAL STEP REQUIRED:"
  report "  1. SSH to server and run: ~/bin/cloudflared tunnel login"
  report "  2. Complete browser auth, then: ~/bin/cloudflared tunnel create sentinel-cloud"
  report "  3. Re-run finish script or configure ~/.cloudflared/config.yml manually"
fi

report ""
report "--- Resources ---"
report "RAM: $(free -h | awk '/^Mem:/ {print $2 " total, " $3 " used, " $7 " available"}')"
report "Disk: $(df -h / | awk 'NR==2 {print $2 " total, " $3 " used, " $4 " free (" $5 ")"}')"

report ""
report "--- Node ---"
report "Node: $(node -v) | npm: $(npm -v)"

report ""
report "=== COMPLETE ==="
cat "$REPORT"
