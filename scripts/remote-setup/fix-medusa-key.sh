#!/usr/bin/env bash
set -euo pipefail
PASS="maddy123"
sshpass -p "$PASS" scp -o StrictHostKeyChecking=no \
  "$(dirname "$0")/api-tunnel-env.sh" sentinel@192.168.0.117:/tmp/api-tunnel-env.sh
sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no sentinel@192.168.0.117 \
  'bash /tmp/api-tunnel-env.sh 2>&1 | tail -40'
