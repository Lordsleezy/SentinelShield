#!/bin/bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
SUDO_PASS="${SUDO_PASS:-maddy123}"

sudo() {
  if command sudo -n true 2>/dev/null; then
    command sudo "$@"
  else
    echo "$SUDO_PASS" | command sudo -S "$@"
  fi
}

log() { echo ">>> $*"; }

# Load nvm
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

REPORT="/tmp/sentinel-medusa-report.txt"
: > "$REPORT"

report() { echo "$*" | tee -a "$REPORT"; }

# ============================================================
# 1. POSTGRESQL
# ============================================================
log "1. PostgreSQL setup"

if ! command -v psql >/dev/null 2>&1; then
  sudo apt-get update -qq
  sudo apt-get install -y -qq postgresql postgresql-contrib
fi

sudo systemctl enable postgresql
sudo systemctl start postgresql

PG_VER=$(psql --version | grep -oE '[0-9]+' | head -1)
report "PostgreSQL version: $(psql --version)"

# Create user and database (idempotent)
sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='sentinel'" | grep -q 1 || \
  sudo -u postgres psql -c "CREATE USER sentinel WITH PASSWORD 'maddy123';"

sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='sentinel_market'" | grep -q 1 || \
  sudo -u postgres psql -c "CREATE DATABASE sentinel_market OWNER sentinel;"

sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE sentinel_market TO sentinel;"
sudo -u postgres psql -d sentinel_market -c "GRANT ALL ON SCHEMA public TO sentinel;"
sudo -u postgres psql -d sentinel_market -c "ALTER DATABASE sentinel_market OWNER TO sentinel;"

report "Database sentinel_market: $(sudo -u postgres psql -tc \"SELECT datname FROM pg_database WHERE datname='sentinel_market'\")"

# ============================================================
# 2. MEDUSA V2
# ============================================================
log "2. Medusa v2 setup"

DB_URL="postgresql://sentinel:maddy123@localhost:5432/sentinel_market"
MEDUSA_DIR="/opt/sentinel/medusa"

sudo mkdir -p /opt/sentinel
sudo chown sentinel:sentinel /opt/sentinel

if [ ! -f "$MEDUSA_DIR/package.json" ]; then
  log "Creating Medusa app in $MEDUSA_DIR"
  cd /opt/sentinel
  rm -rf "$MEDUSA_DIR"
  # Non-interactive: pipe N to skip Next.js storefront prompt
  echo "N" | npx --yes create-medusa-app@latest medusa \
    --db-url "$DB_URL" \
    --no-browser \
    --use-npm \
    --verbose 2>&1 | tail -50
fi

if [ ! -f "$MEDUSA_DIR/package.json" ]; then
  report "ERROR: Medusa app creation failed"
  exit 1
fi

cd "$MEDUSA_DIR"

# Write .env
cat > .env << ENVEOF
DATABASE_URL=$DB_URL
STORE_CORS=http://localhost:8000,https://legion.sentinelprime.org
ADMIN_CORS=http://localhost:7001,http://localhost:9000,https://legion.sentinelprime.org
AUTH_CORS=http://localhost:7001,http://localhost:9000,https://legion.sentinelprime.org
REDIS_URL=redis://localhost:6379
JWT_SECRET=$(openssl rand -hex 32)
COOKIE_SECRET=$(openssl rand -hex 32)
PORT=9000
ENVEOF

# Install redis if needed (Medusa often needs it)
if ! command -v redis-server >/dev/null 2>&1; then
  sudo apt-get install -y -qq redis-server
  sudo systemctl enable redis-server
  sudo systemctl start redis-server
fi

npm install 2>&1 | tail -5

# Run migrations (create-medusa-app may have run them; ensure)
log "Running migrations..."
npx medusa db:migrate 2>&1 | tail -20 || npx medusa migrations run 2>&1 | tail -20 || true

# Create admin user (idempotent - ignore if exists)
log "Creating admin user..."
npx medusa user --email admin@sentinelprime.org --password maddy123 2>&1 || \
  npx medusa user -e admin@sentinelprime.org -p maddy123 2>&1 || true

# Build for production start
log "Building Medusa..."
npm run build 2>&1 | tail -20

MEDUSA_VER=$(node -e "console.log(require('./package.json').dependencies['@medusajs/medusa'] || require('./package.json').devDependencies['@medusajs/medusa'] || 'unknown')" 2>/dev/null || echo "unknown")
report "Medusa version: $MEDUSA_VER"

# Systemd service
sudo tee /etc/systemd/system/sentinel-medusa.service > /dev/null << 'SVCEOF'
[Unit]
Description=Sentinel Medusa v2 Store
After=network.target postgresql.service redis-server.service
Wants=postgresql.service redis-server.service

[Service]
Type=simple
User=sentinel
Group=sentinel
WorkingDirectory=/opt/sentinel/medusa
EnvironmentFile=/opt/sentinel/medusa/.env
Environment=NODE_ENV=production
ExecStart=/bin/bash -lc 'source ~/.nvm/nvm.sh && nvm use default && npm run start'
Restart=on-failure
RestartSec=10
StandardOutput=append:/opt/sentinel/logs/medusa.log
StandardError=append:/opt/sentinel/logs/medusa.log

[Install]
WantedBy=multi-user.target
SVCEOF

sudo systemctl daemon-reload
sudo systemctl enable sentinel-medusa
sudo systemctl restart sentinel-medusa

log "Waiting for Medusa to start..."
for i in $(seq 1 30); do
  if curl -sf http://localhost:9000/health >/dev/null 2>&1; then
    report "Medusa health check: OK"
    break
  fi
  sleep 3
done

report "Medusa service: $(systemctl is-active sentinel-medusa)"
report "Medusa admin URL: http://localhost:9000/app"

echo "=== STEP 1-2 DONE ==="
