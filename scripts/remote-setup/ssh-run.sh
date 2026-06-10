#!/bin/bash
HOST="sentinel@192.168.0.117"
PASS="maddy123"
SCRIPT="$1"

sshpass -p "$PASS" scp -o StrictHostKeyChecking=no "$SCRIPT" "${HOST}:/tmp/remote_script.sh"
EXTRA="${2:-}"
if [ -n "$EXTRA" ] && [ -f "$EXTRA" ]; then
  sshpass -p "$PASS" scp -o StrictHostKeyChecking=no "$EXTRA" "${HOST}:/tmp/$(basename "$EXTRA")"
fi
sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no "$HOST" "chmod +x /tmp/remote_script.sh && SUDO_PASS='$PASS' bash /tmp/remote_script.sh"
