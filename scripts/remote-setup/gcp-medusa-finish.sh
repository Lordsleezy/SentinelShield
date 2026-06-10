#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
SUDO_PASS="${SUDO_PASS:-maddy123}"
USER_NAME="$(whoami)"
HOME_DIR="$HOME"
MEDUSA_ROOT="/opt/medusa"
DB_URL="postgresql://sentinel:maddy123@localhost:5432/sentinel_market"
REPORT="/tmp/gcp-medusa-final-report.txt"

sudo() {
  if command sudo -n true 2>/dev/null; then command sudo "$@"
  else echo "$SUDO_PASS" | command sudo -S "$@"; fi
}

log() { echo ">>> $*"; }
report() { echo "$*" | tee -a "$REPORT"; }

export NVM_DIR="$HOME_DIR/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
nvm use 20 >/dev/null

: > "$REPORT"
report "========================================"
report "   GCP MEDUSA SETUP FINAL REPORT"
report "   $(date)"
report "========================================"

# Ensure dirs
sudo mkdir -p "$MEDUSA_ROOT/logs"
sudo chown -R "$USER_NAME:$USER_NAME" "$MEDUSA_ROOT"

# Install Medusa if missing
if [ ! -f "$MEDUSA_ROOT/package.json" ] && [ ! -f "$MEDUSA_ROOT/apps/backend/package.json" ]; then
  log "Creating Medusa app in $MEDUSA_ROOT"
  rm -rf "$MEDUSA_ROOT"/*
  cd "$MEDUSA_ROOT"
  printf 'N\n' | npx --yes create-medusa-app@latest . \
    --db-url "$DB_URL" \
    --no-browser \
    --use-npm 2>&1 | tee /tmp/medusa-create.log | tail -40
fi

if [ -f "$MEDUSA_ROOT/apps/backend/package.json" ]; then
  MEDUSA_DIR="$MEDUSA_ROOT/apps/backend"
elif [ -f "$MEDUSA_ROOT/package.json" ]; then
  MEDUSA_DIR="$MEDUSA_ROOT"
else
  report "ERROR: Medusa install failed"
  tail -30 /tmp/medusa-create.log 2>/dev/null | tee -a "$REPORT"
  exit 1
fi

cd "$MEDUSA_DIR"
JWT_SECRET=$(openssl rand -hex 32)
COOKIE_SECRET=$(openssl rand -hex 32)
cat > .env << ENVEOF
DATABASE_URL=$DB_URL
STORE_CORS=http://localhost:8000,https://legion.sentinelprime.org,https://market.sentinelprime.org
ADMIN_CORS=http://localhost:7001,http://localhost:9000,https://legion.sentinelprime.org
AUTH_CORS=http://localhost:7001,http://localhost:9000,https://legion.sentinelprime.org
REDIS_URL=redis://localhost:6379
JWT_SECRET=$JWT_SECRET
COOKIE_SECRET=$COOKIE_SECRET
PORT=9000
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

cat > /tmp/sentinel-medusa.service << SVCEOF
[Unit]
Description=Sentinel Medusa v2 Store
After=network.target postgresql.service redis-server.service
Wants=postgresql.service redis-server.service

[Service]
Type=simple
User=$USER_NAME
Group=$USER_NAME
WorkingDirectory=$MEDUSA_DIR
EnvironmentFile=$MEDUSA_DIR/.env
Environment=NODE_ENV=development
Environment=PATH=$NODE_PATH:/usr/local/bin:/usr/bin:/bin
ExecStart=$NPX_BIN medusa develop
Restart=on-failure
RestartSec=10
StandardOutput=append:/opt/medusa/logs/medusa.log
StandardError=append:/opt/medusa/logs/medusa.log

[Install]
WantedBy=multi-user.target
SVCEOF

sudo cp /tmp/sentinel-medusa.service /etc/systemd/system/sentinel-medusa.service
sudo systemctl daemon-reload
sudo systemctl enable sentinel-medusa
sudo systemctl restart sentinel-medusa

MEDUSA_OK=false
for i in $(seq 1 60); do
  curl -sf http://localhost:9000/health >/dev/null 2>&1 && MEDUSA_OK=true && break
  sleep 5
done

# UFW
if ! sudo ufw status | grep -q "Status: active"; then
  sudo ufw --force reset
  sudo ufw default deny incoming
  sudo ufw default allow outgoing
  sudo ufw allow 22/tcp
  sudo ufw allow 80/tcp
  sudo ufw allow 443/tcp
  sudo ufw allow 9000/tcp
  echo "y" | sudo ufw enable
fi

# API key
MEDUSA_API_KEY=""
MEDUSA_API_URL="http://localhost:9000"
if [ "$MEDUSA_OK" = true ]; then
  TOKEN=$(curl -sf -X POST "$MEDUSA_API_URL/auth/user/emailpass" \
    -H "Content-Type: application/json" \
    -d '{"email":"admin@sentinelprime.org","password":"maddy123"}' | \
    python3 -c "import sys,json; print(json.load(sys.stdin).get('token',''))" 2>/dev/null || echo "")
  if [ -n "$TOKEN" ]; then
    MEDUSA_API_KEY=$(curl -sf -X POST "$MEDUSA_API_URL/admin/api-keys" \
      -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/json" \
      -d '{"title":"Sentinel Server Key","type":"secret"}' | \
      python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('api_key',d).get('token',''))" 2>/dev/null || echo "")
  fi
fi

cat > /opt/medusa/.env.shared << ENVEOF
MEDUSA_API_URL=$MEDUSA_API_URL
MEDUSA_API_KEY=$MEDUSA_API_KEY
ENVEOF
chmod 600 /opt/medusa/.env.shared

# Cloudflared
CF_BIN="/usr/local/bin/cloudflared"
if [ ! -x "$CF_BIN" ]; then
  curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64" -o /tmp/cloudflared
  sudo install -m 755 /tmp/cloudflared "$CF_BIN"
fi

mkdir -p "$HOME_DIR/.cloudflared"
TUNNEL_READY=false
TUNNEL_ID=""
if "$CF_BIN" tunnel list 2>/dev/null | grep -q "sentinel-cloud"; then
  TUNNEL_ID=$("$CF_BIN" tunnel list 2>/dev/null | awk '/sentinel-cloud/ {print $1; exit}')
  TUNNEL_READY=true
else
  CREATE_OUT=$("$CF_BIN" tunnel create sentinel-cloud 2>&1 || true)
  if echo "$CREATE_OUT" | grep -qE '[0-9a-f-]{36}'; then
    TUNNEL_ID=$(echo "$CREATE_OUT" | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | head -1)
    TUNNEL_READY=true
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
  cat > /tmp/sentinel-cloudflared.service << CFUNIT
[Unit]
Description=Sentinel Cloudflare Tunnel
After=network.target sentinel-medusa.service

[Service]
Type=simple
User=$USER_NAME
ExecStart=$CF_BIN tunnel --config $CONFIG run
Restart=on-failure
RestartSec=10
StandardOutput=append:/opt/medusa/logs/cloudflared.log
StandardError=append:/opt/medusa/logs/cloudflared.log

[Install]
WantedBy=multi-user.target
CFUNIT
  sudo cp /tmp/sentinel-cloudflared.service /etc/systemd/system/sentinel-cloudflared.service
  sudo systemctl daemon-reload
  sudo systemctl enable sentinel-cloudflared
  sudo systemctl restart sentinel-cloudflared || true
fi

report ""
report "--- PostgreSQL ---"
report "Version: $(psql --version)"
report "Service: $(systemctl is-active postgresql) / $(systemctl is-enabled postgresql)"
report "Database: sentinel_market"

report ""
report "--- Medusa ---"
report "Version: $MEDUSA_VER"
report "Path: $MEDUSA_DIR"
report "Service: $(systemctl is-active sentinel-medusa) / $(systemctl is-enabled sentinel-medusa)"
report "Health: $(curl -sf http://localhost:9000/health && echo OK || echo FAILED)"
report "Admin: http://localhost:9000/app"
report "Public: https://legion.sentinelprime.org/app"

report ""
report "--- UFW ---"
sudo ufw status | tee -a "$REPORT"

report ""
report "--- API Key ---"
if [ -n "$MEDUSA_API_KEY" ]; then
  report "Generated: ${MEDUSA_API_KEY:0:12}... (saved /opt/medusa/.env.shared)"
else
  report "Not generated yet"
fi

report ""
report "--- Cloudflare ---"
report "cloudflared: $($CF_BIN --version 2>&1 | head -1)"
if [ "$TUNNEL_READY" = true ]; then
  report "Tunnel: sentinel-cloud ($TUNNEL_ID)"
  report "Route: legion.sentinelprime.org -> localhost:9000"
  report "Service: $(systemctl is-active sentinel-cloudflared 2>/dev/null || echo inactive)"
else
  report "MANUAL: Run 'cloudflared tunnel login' then 'cloudflared tunnel create sentinel-cloud'"
fi

report ""
report "--- Resources ---"
report "RAM: $(free -h | awk '/^Mem:/ {print $2 " total, " $3 " used, " $7 " available"}')"
report "Disk: $(df -h / | awk 'NR==2 {print $2 " total, " $3 " used, " $4 " free"}')"

report ""
report "=== COMPLETE ==="
cat "$REPORT"
