#!/bin/bash
SUDO_PASS="${SUDO_PASS:-maddy123}"
sudo() { echo "$SUDO_PASS" | command sudo -S "$@"; }

cat /etc/systemd/system/sentinel-medusa.service 2>/dev/null || echo "missing"
echo "---"
systemd-analyze verify /etc/systemd/system/sentinel-medusa.service 2>&1 || true
ls -la /etc/systemd/system/sentinel-medusa.service 2>/dev/null
