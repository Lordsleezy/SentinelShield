#!/bin/bash
set -euo pipefail
SUDO_PASS="${SUDO_PASS:-maddy123}"
sudo() { echo "$SUDO_PASS" | command sudo -S "$@"; }

sudo rm -f /etc/systemd/system/sentinel-medusa.service
sudo systemctl unmask sentinel-medusa 2>/dev/null || true

# Write unit file without sudo (avoid stdin conflict with sudo -S)
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
Environment=NODE_ENV=production
Environment=PATH=/usr/local/bin:/usr/bin:/bin
ExecStart=/usr/bin/npx medusa start
Restart=on-failure
RestartSec=10
StandardOutput=append:/opt/sentinel/logs/medusa.log
StandardError=append:/opt/sentinel/logs/medusa.log

[Install]
WantedBy=multi-user.target
SVCEOF

sudo cp /tmp/sentinel-medusa.service /etc/systemd/system/sentinel-medusa.service
sudo mkdir -p /opt/sentinel/logs
sudo chown sentinel:sentinel /opt/sentinel/logs

sudo systemctl daemon-reload
sudo systemctl enable sentinel-medusa
sudo systemctl start sentinel-medusa

echo "Waiting for Medusa..."
for i in $(seq 1 30); do
  if curl -sf http://localhost:9000/health >/dev/null 2>&1; then
    echo "Health OK on attempt $i"
    break
  fi
  sleep 2
done

echo "Status: $(systemctl is-active sentinel-medusa)"
curl -s http://localhost:9000/health || true
echo ""
tail -15 /opt/sentinel/logs/medusa.log
