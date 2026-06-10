#!/bin/bash
SUDO_PASS="${SUDO_PASS:-maddy123}"
sudo() { echo "$SUDO_PASS" | command sudo -S "$@"; }

cat > /tmp/sentinel-medusa.service << 'EOF'
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
EOF

sudo cp /tmp/sentinel-medusa.service /etc/systemd/system/sentinel-medusa.service
sudo systemctl daemon-reload
echo "Service updated (removed ExecStartPre build step)"
