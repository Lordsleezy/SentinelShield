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
  if command sudo -n true 2>/dev/null; then
    command sudo "$@"
  else
    echo "$SUDO_PASS" | command sudo -S "$@"
  fi
}

log() { echo ">>> $*"; }
report() { echo "$*" | tee -a "$REPORT"; }

: > "$REPORT"
report "========================================"
report "   GCP MEDUSA SETUP FINAL REPORT"
report "   $(date)"
report "========================================"

# ============================================================
# 1. SYSTEM PACKAGES
# ============================================================
log "1. System packages"
sudo apt-get update -qq
sudo apt-get upgrade -y -qq
sudo apt-get install -y -qq \
  git curl wget ca-certificates gnupg build-essential \
  python3 python3-pip python3-venv \
  postgresql postgresql-contrib redis-server \
  ufw openssl jq

# Node via nvm
if [ ! -d "$HOME_DIR/.nvm" ]; then
  curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
fi
export NVM_DIR="$HOME_DIR/.nvm"
# shellcheck source=/dev/null
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
nvm install 20
nvm alias default 20
nvm use 20

report ""
report "--- System ---"
report "Node: $(node -v)"
report "npm: $(npm -v)"
report "Python: $(python3 --version)"
report "git: $(git --version | head -1)"

# ============================================================
# PostgreSQL
# ============================================================
log "PostgreSQL setup"
sudo systemctl enable postgresql
sudo systemctl start postgresql

sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='sentinel'" | grep -q 1 || \
  sudo -u postgres psql -c "CREATE USER sentinel WITH PASSWORD 'maddy123';"

sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='sentinel_market'" | grep -q 1 || \
  sudo -u postgres psql -c "CREATE DATABASE sentinel_market OWNER sentinel;"

sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE sentinel_market TO sentinel;"
sudo -u postgres psql -d sentinel_market -c "GRANT ALL ON SCHEMA public TO sentinel;"
sudo -u postgres psql -d sentinel_market -c "ALTER DATABASE sentinel_market OWNER TO sentinel;"

sudo systemctl enable redis-server
sudo systemctl start redis-server

report ""
report "--- PostgreSQL ---"
report "Version: $(psql --version)"
report "Service: $(systemctl is-active postgresql) / $(systemctl is-enabled postgresql)"
report "Database: sentinel_market (owner: sentinel)"

# ============================================================
# 2. MEDUSA V2
# ============================================================
log "2. Medusa v2"
sudo mkdir -p "$MEDUSA_ROOT" /opt/medusa/logs
sudo chown -R "$USER_NAME:$USER_NAME" "$MEDUSA_ROOT"

if [ ! -f "$MEDUSA_ROOT/package.json" ] && [ ! -f "$MEDUSA_ROOT/apps/backend/package.json" ]; then
  log "Creating Medusa app..."
  cd /opt
  rm -rf medusa
  mkdir -p medusa
  cd medusa
  # Skip bundled Next.js storefront
  printf 'N\n' | npx --yes create-medusa-app@latest . \
    --db-url "$DB_URL" \
    --no-browser \
    --use-npm 2>&1 | tail -80
fi

# Detect backend path
if [ -f "$MEDUSA_ROOT/apps/backend/package.json" ]; then
  MEDUSA_DIR="$MEDUSA_ROOT/apps/backend"
  MEDUSA_WORK="$MEDUSA_ROOT"
elif [ -f "$MEDUSA_ROOT/package.json" ]; then
  MEDUSA_DIR="$MEDUSA_ROOT"
  MEDUSA_WORK="$MEDUSA_ROOT"
else
  report "ERROR: Medusa installation failed — no package.json found"
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
  cd "$MEDUSA_ROOT"
  npm install 2>&1 | tail -5
  cd "$MEDUSA_DIR"
fi

log "Migrations..."
npx medusa db:migrate 2>&1 | tail -20

log "Admin user..."
npx medusa user --email admin@sentinelprime.org --password maddy123 2>&1 || \
  npx medusa user -e admin@sentinelprime.org -p maddy123 2>&1 || true

MEDUSA_VER=$(node -e "
const p=require('$MEDUSA_ROOT/package.json');
console.log(p.dependencies?.['@medusajs/medusa']||p.devDependencies?.['@medusajs/medusa']||'see package.json');
" 2>/dev/null || echo "unknown")

# Systemd — use medusa develop for reliability (same as home server)
NODE_BIN=$(which node)
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
Environment=PATH=$HOME_DIR/.nvm/versions/node/v20.20.1/bin:/usr/local/bin:/usr/bin:/bin
ExecStart=$NPX_BIN medusa develop
Restart=on-failure
RestartSec=10
StandardOutput=append:/opt/medusa/logs/medusa.log
StandardError=append:/opt/medusa/logs/medusa.log

[Install]
WantedBy=multi-user.target
SVCEOF

# Fix node path dynamically
NODE_PATH=$(dirname "$(which node)")
sed -i "s|Environment=PATH=.*|Environment=PATH=$NODE_PATH:/usr/local/bin:/usr/bin:/bin|" /tmp/sentinel-medusa.service

sudo cp /tmp/sentinel-medusa.service /etc/systemd/system/sentinel-medusa.service
sudo systemctl daemon-reload
sudo systemctl enable sentinel-medusa
sudo systemctl restart sentinel-medusa

log "Waiting for Medusa..."
MEDUSA_OK=false
for i in $(seq 1 60); do
  if curl -sf http://localhost:9000/health >/dev/null 2>&1; then
    MEDUSA_OK=true
    break
  fi
  sleep 5
done

report ""
report "--- Medusa ---"
report "Version: $MEDUSA_VER"
report "Path: $MEDUSA_DIR"
report "Service: $(systemctl is-active sentinel-medusa) / $(systemctl is-enabled sentinel-medusa)"
report "Health: $(curl -sf http://localhost:9000/health && echo OK || echo FAILED)"
report "Admin panel: http://localhost:9000/app"
report "Public (via tunnel): https://legion.sentinelprime.org/app"

# ============================================================
# 3. FIREWALL
# ============================================================
log "3. UFW"
sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 9000/tcp
echo "y" | sudo ufw enable

report ""
report "--- UFW ---"
report "Status: $(sudo ufw status | head -1)"
sudo ufw status numbered | tee -a "$REPORT"

# ============================================================
# 4. API KEY
# ============================================================
log "4. API key"
MEDUSA_API_KEY=""
MEDUSA_API_URL="http://localhost:9000"

if [ "$MEDUSA_OK" = true ]; then
  LOGIN_RESP=$(curl -sf -X POST "$MEDUSA_API_URL/auth/user/emailpass" \
    -H "Content-Type: application/json" \
    -d '{"email":"admin@sentinelprime.org","password":"maddy123"}' || echo "")

  TOKEN=$(echo "$LOGIN_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('token',''))" 2>/dev/null || echo "")

  if [ -n "$TOKEN" ]; then
    API_RESP=$(curl -sf -X POST "$MEDUSA_API_URL/admin/api-keys" \
      -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/json" \
      -d '{"title":"Sentinel Server Key","type":"secret"}' || echo "")
    MEDUSA_API_KEY=$(echo "$API_RESP" | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    ak=d.get('api_key',d)
    print(ak.get('token',''))
except: print('')
" 2>/dev/null)
  fi

  if [ -z "$MEDUSA_API_KEY" ] && [ -d "$MEDUSA_DIR" ]; then
    MEDUSA_API_KEY=$(cd "$MEDUSA_DIR" && npx medusa exec "
      const { createApiKeysWorkflow } = require('@medusajs/medusa/core-flows');
      module.exports = async ({ container }) => {
        const { result } = await createApiKeysWorkflow(container).run({
          input: { api_keys: [{ title: 'Sentinel Server Key', type: 'secret', created_by: '' }] }
        });
        console.log(result[0].token);
      };
    " 2>/dev/null | tail -1 || echo "")
  fi
fi

cat > /opt/medusa/.env.shared << ENVEOF
MEDUSA_API_URL=$MEDUSA_API_URL
MEDUSA_API_KEY=$MEDUSA_API_KEY
ENVEOF
chmod 600 /opt/medusa/.env.shared

report ""
report "--- API Key ---"
if [ -n "$MEDUSA_API_KEY" ]; then
  report "Generated: ${MEDUSA_API_KEY:0:12}...${MEDUSA_API_KEY: -4}"
  report "Saved: /opt/medusa/.env.shared"
else
  report "API key generation failed — create manually in admin panel"
fi

# ============================================================
# 5. CLOUDFLARE TUNNEL
# ============================================================
log "5. Cloudflared"
CF_BIN="/usr/local/bin/cloudflared"
if [ ! -x "$CF_BIN" ]; then
  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64) CF_ARCH=amd64 ;;
    aarch64|arm64) CF_ARCH=arm64 ;;
    *) CF_ARCH=amd64 ;;
  esac
  curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CF_ARCH}" -o /tmp/cloudflared
  sudo install -m 755 /tmp/cloudflared "$CF_BIN"
fi

report ""
report "--- Cloudflare Tunnel ---"
report "cloudflared: $($CF_BIN --version 2>&1 | head -1)"

mkdir -p "$HOME_DIR/.cloudflared"
TUNNEL_READY=false
TUNNEL_ID=""

if "$CF_BIN" tunnel list 2>/dev/null | grep -q "sentinel-cloud"; then
  TUNNEL_ID=$("$CF_BIN" tunnel list 2>/dev/null | awk '/sentinel-cloud/ {print $1; exit}')
  TUNNEL_READY=true
  report "Existing tunnel found: sentinel-cloud ($TUNNEL_ID)"
else
  CREATE_OUT=$("$CF_BIN" tunnel create sentinel-cloud 2>&1 || true)
  if echo "$CREATE_OUT" | grep -qE 'id|Created tunnel'; then
    TUNNEL_ID=$(echo "$CREATE_OUT" | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | head -1)
    TUNNEL_READY=true
    report "Created tunnel: sentinel-cloud ($TUNNEL_ID)"
  else
    report "MANUAL STEP REQUIRED: Cloudflare authentication needed"
    report "Run on server as $USER_NAME:"
    report "  cloudflared tunnel login"
    report "  cloudflared tunnel create sentinel-cloud"
    report "Then re-run tunnel config section or deploy script"
    echo "$CREATE_OUT" | tail -5 | tee -a "$REPORT"
  fi
fi

if [ "$TUNNEL_READY" = true ] && [ -n "$TUNNEL_ID" ]; then
  CREDS="$HOME_DIR/.cloudflared/${TUNNEL_ID}.json"
  CONFIG="$HOME_DIR/.cloudflared/config.yml"

  cat > "$CONFIG" << CFEOF
tunnel: $TUNNEL_ID
credentials-file: $CREDS

ingress:
  - hostname: legion.sentinelprime.org
    service: http://localhost:9000
  - service: http_status:404
CFEOF

  cat > /tmp/sentinel-cloudflared.service << CFUNIT
[Unit]
Description=Sentinel Cloudflare Tunnel (sentinel-cloud)
After=network.target sentinel-medusa.service
Wants=network-online.target

[Service]
Type=simple
User=$USER_NAME
Group=$USER_NAME
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

  report "Tunnel config: $CONFIG"
  report "Route: legion.sentinelprime.org -> http://localhost:9000"
  report "Service: $(systemctl is-active sentinel-cloudflared 2>/dev/null || echo inactive)"
  report "NOTE: Add DNS CNAME legion.sentinelprime.org -> ${TUNNEL_ID}.cfargotunnel.com in Cloudflare dashboard if not done"
fi

# ============================================================
# RESOURCES
# ============================================================
report ""
report "--- Resources ---"
report "RAM: $(free -h | awk '/^Mem:/ {print $2 " total, " $3 " used, " $7 " available"}')"
report "Disk: $(df -h / | awk 'NR==2 {print $2 " total, " $3 " used, " $4 " free (" $5 " used)"}')"

report ""
report "--- Services ---"
for svc in postgresql redis-server sentinel-medusa sentinel-cloudflared; do
  report "  $svc: $(systemctl is-active $svc 2>/dev/null || echo not-found) / $(systemctl is-enabled $svc 2>/dev/null || echo not-found)"
done

report ""
report "=== SETUP COMPLETE ==="
cat "$REPORT"
