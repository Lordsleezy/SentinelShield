#!/usr/bin/env bash
set -euo pipefail

HOST="pgg124@136.118.148.167"
PASS="maddy123"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

sshpass -p "$PASS" scp -o StrictHostKeyChecking=no -o ConnectTimeout=30 \
  "$SCRIPT_DIR/gcp-medusa-setup.sh" "$HOST:/tmp/gcp-medusa-setup.sh"

sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=30 "$HOST" \
  "chmod +x /tmp/gcp-medusa-setup.sh && bash /tmp/gcp-medusa-setup.sh 2>&1 | tee /tmp/gcp-setup.log"
