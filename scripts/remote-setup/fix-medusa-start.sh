#!/bin/bash
set -euo pipefail
SUDO_PASS="${SUDO_PASS:-maddy123}"
sudo() { echo "$SUDO_PASS" | command sudo -S "$@"; }

cd /opt/sentinel/medusa/apps/backend

echo "=== Build artifacts ==="
find .medusa -name 'index.html' 2>/dev/null
ls -la .medusa/server/public/admin/ 2>/dev/null || true

echo "=== Rebuild ==="
/usr/bin/npx medusa build 2>&1 | tail -5

echo "=== Try medusa develop (background test) ==="
timeout 20 /usr/bin/npx medusa develop 2>&1 | tail -20 &
DEVPID=$!
sleep 15
curl -sf http://localhost:9000/health && echo " develop health OK" || echo " develop health fail"
kill $DEVPID 2>/dev/null || true
wait $DEVPID 2>/dev/null || true

echo "=== Try medusa start direct ==="
timeout 20 /usr/bin/npx medusa start 2>&1 | tail -15 || true

# Use develop mode in systemd if start fails in production
cat > /tmp/sentinel-medusa.service << 'SVCEOF'
[Unit]
Description=Sentinel Medusa v2 Store
After=network.target postgresql.service redis-server.service
Wants=postgresql.service redis-server.service

[Service]
Type=simple
User=sentinel
Group=sentinel
WorkingDirectory=/opt/sentinel/medusa/apps/backend
EnvironmentFile=/opt/sentinel/medusa/apps/backend/.env
Environment=NODE_ENV=development
Environment=PATH=/usr/local/bin:/usr/bin:/bin
ExecStart=/usr/bin/npx medusa develop
Restart=on-failure
RestartSec=10
StandardOutput=append:/opt/sentinel/logs/medusa.log
StandardError=append:/opt/sentinel/logs/medusa.log

[Install]
WantedBy=multi-user.target
SVCEOF

sudo cp /tmp/sentinel-medusa.service /etc/systemd/system/sentinel-medusa.service
sudo systemctl daemon-reload
sudo systemctl restart sentinel-medusa

sleep 20
systemctl is-active sentinel-medusa
curl -sf http://localhost:9000/health && echo " OK" || curl -s http://localhost:9000/ | head -3
tail -10 /opt/sentinel/logs/medusa.log
