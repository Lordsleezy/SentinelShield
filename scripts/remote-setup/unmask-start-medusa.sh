#!/bin/bash
SUDO_PASS="${SUDO_PASS:-maddy123}"
sudo() { echo "$SUDO_PASS" | command sudo -S "$@"; }

sudo systemctl unmask sentinel-medusa
sudo systemctl daemon-reload
sudo systemctl enable sentinel-medusa
sudo systemctl restart sentinel-medusa
sleep 5
systemctl is-active sentinel-medusa
curl -sf http://localhost:9000/health && echo " health OK" || echo "health FAIL"
tail -10 /opt/sentinel/logs/medusa.log
