#!/bin/bash
set -euo pipefail

SUDO_PASS="${SUDO_PASS:-maddy123}"

sudo() {
  if command sudo -n true 2>/dev/null; then
    command sudo "$@"
  else
    echo "$SUDO_PASS" | command sudo -S "$@"
  fi
}

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

MEDUSA_ROOT="/opt/sentinel/medusa"
DB_URL="postgresql://sentinel:maddy123@localhost:5432/sentinel_market"

# Detect backend directory (monorepo vs flat)
if [ -f "$MEDUSA_ROOT/apps/backend/package.json" ]; then
  MEDUSA_DIR="$MEDUSA_ROOT/apps/backend"
  echo "Using monorepo backend: $MEDUSA_DIR"
elif [ -f "$MEDUSA_ROOT/package.json" ]; then
  MEDUSA_DIR="$MEDUSA_ROOT"
else
  echo "ERROR: No Medusa package.json found"
  exit 1
fi

# Redis
if ! command -v redis-server >/dev/null 2>&1; then
  sudo apt-get update -qq
  sudo apt-get install -y -qq redis-server
fi
sudo systemctl enable redis-server
sudo systemctl start redis-server

cd "$MEDUSA_DIR"

# Ensure .env
if [ ! -f .env ]; then
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
else
  grep -q '^PORT=' .env && sed -i 's/^PORT=.*/PORT=9000/' .env || echo "PORT=9000" >> .env
  grep -q '^DATABASE_URL=' .env && sed -i "s|^DATABASE_URL=.*|DATABASE_URL=$DB_URL|" .env || echo "DATABASE_URL=$DB_URL" >> .env
  grep -q '^REDIS_URL=' .env || echo "REDIS_URL=redis://localhost:6379" >> .env
fi

echo "=== .env ==="
grep -v SECRET .env

# Install deps at root if monorepo
if [ "$MEDUSA_DIR" != "$MEDUSA_ROOT" ]; then
  cd "$MEDUSA_ROOT"
  npm install 2>&1 | tail -3
  cd "$MEDUSA_DIR"
fi

echo "=== Migrations ==="
npx medusa db:migrate 2>&1 | tail -15

echo "=== Admin user ==="
npx medusa user --email admin@sentinelprime.org --password maddy123 2>&1 || \
  npx medusa user -e admin@sentinelprime.org -p maddy123 2>&1 || true

echo "=== Build ==="
cd "$MEDUSA_ROOT"
npm run build 2>&1 | tail -20

# Systemd - run from monorepo root with workspace command
sudo tee /etc/systemd/system/sentinel-medusa.service > /dev/null << SVCEOF
[Unit]
Description=Sentinel Medusa v2 Store
After=network.target postgresql.service redis-server.service
Wants=postgresql.service redis-server.service

[Service]
Type=simple
User=sentinel
Group=sentinel
WorkingDirectory=$MEDUSA_ROOT
EnvironmentFile=$MEDUSA_DIR/.env
Environment=NODE_ENV=production
ExecStart=/bin/bash -lc 'source \$HOME/.nvm/nvm.sh && nvm use default && cd $MEDUSA_DIR && npx medusa start'
Restart=on-failure
RestartSec=10
StandardOutput=append:/opt/sentinel/logs/medusa.log
StandardError=append:/opt/sentinel/logs/medusa.log

[Install]
WantedBy=multi-user.target
SVCEOF

sudo mkdir -p /opt/sentinel/logs
sudo chown sentinel:sentinel /opt/sentinel/logs
sudo systemctl daemon-reload
sudo systemctl enable sentinel-medusa
sudo systemctl restart sentinel-medusa

echo "=== Waiting for Medusa ==="
for i in $(seq 1 40); do
  if curl -sf http://localhost:9000/health >/dev/null 2>&1; then
    echo "Medusa health: OK"
    break
  fi
  if curl -sf http://localhost:9000/ >/dev/null 2>&1; then
    echo "Medusa responding on :9000"
    break
  fi
  sleep 3
  echo "  attempt $i..."
done

systemctl is-active sentinel-medusa
journalctl -u sentinel-medusa -n 20 --no-pager 2>/dev/null || tail -20 /opt/sentinel/logs/medusa.log 2>/dev/null || true

echo "=== MEDUSA DONE ==="
