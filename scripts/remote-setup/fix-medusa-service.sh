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

MEDUSA_DIR="/opt/sentinel/medusa/apps/backend"
NODE_BIN=$(command -v node)
NPX_BIN=$(command -v npx)

echo "Node: $NODE_BIN ($($NODE_BIN -v))"
echo "Npx: $NPX_BIN"

cd "$MEDUSA_DIR"

# Fix .env
grep -q '^PORT=' .env 2>/dev/null && sed -i 's/^PORT=.*/PORT=9000/' .env || echo "PORT=9000" >> .env
sed -i 's|^STORE_CORS=.*|STORE_CORS=http://localhost:8000,https://legion.sentinelprime.org|' .env
sed -i 's|^ADMIN_CORS=.*|ADMIN_CORS=http://localhost:5173,http://localhost:9000,https://legion.sentinelprime.org|' .env
sed -i 's|^AUTH_CORS=.*|AUTH_CORS=http://localhost:5173,http://localhost:9000,http://localhost:8000,https://legion.sentinelprime.org|' .env

echo "=== Rebuild backend ==="
$NPX_BIN medusa build 2>&1 | tail -10

# Verify admin build exists
ls -la .medusa/server/public/admin/index.html 2>/dev/null || \
  find .medusa -name 'index.html' 2>/dev/null | head -5

sudo tee /etc/systemd/system/sentinel-medusa.service > /dev/null << SVCEOF
[Unit]
Description=Sentinel Medusa v2 Store
After=network.target postgresql.service redis-server.service
Wants=postgresql.service redis-server.service

[Service]
Type=simple
User=sentinel
Group=sentinel
WorkingDirectory=$MEDUSA_DIR
EnvironmentFile=$MEDUSA_DIR/.env
Environment=NODE_ENV=production
Environment=PATH=/usr/local/bin:/usr/bin:/bin
ExecStart=$NPX_BIN medusa start
Restart=on-failure
RestartSec=10
StandardOutput=append:/opt/sentinel/logs/medusa.log
StandardError=append:/opt/sentinel/logs/medusa.log

[Install]
WantedBy=multi-user.target
SVCEOF

sudo systemctl daemon-reload
sudo systemctl restart sentinel-medusa

echo "=== Waiting ==="
for i in $(seq 1 30); do
  if curl -sf http://localhost:9000/health >/dev/null 2>&1; then
    echo "Health OK"
    break
  fi
  sleep 2
done

systemctl is-active sentinel-medusa
curl -sf http://localhost:9000/health && echo "" || echo "health failed"
tail -5 /opt/sentinel/logs/medusa.log
