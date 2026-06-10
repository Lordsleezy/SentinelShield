#!/bin/bash
# Kill any stuck install, copy SD script, run main install
pkill -f 'bash /tmp/remote_script' 2>/dev/null || true
pkill -f install-services 2>/dev/null || true
sleep 1
cp /tmp/install-sd.sh /opt/sentinel/scripts/install-sd.sh 2>/dev/null || mkdir -p /opt/sentinel/scripts && cp /tmp/install-sd.sh /opt/sentinel/scripts/install-sd.sh
chmod +x /opt/sentinel/scripts/install-sd.sh 2>/dev/null || true
export SUDO_PASS="${SUDO_PASS:-maddy123}"
bash /tmp/install-services.sh
