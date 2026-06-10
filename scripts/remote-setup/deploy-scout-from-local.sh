#!/usr/bin/env bash
set -euo pipefail

HOST="sentinel@192.168.0.117"
PASS="maddy123"
LOCAL_DIR="$(cd "$(dirname "$0")/../../services/scout" && pwd)"

TMP="/tmp/scout-deploy.tar.gz"
tar -czf "$TMP" -C "$LOCAL_DIR" app requirements.txt schema.sql .env.example

sshpass -p "$PASS" scp -o StrictHostKeyChecking=no "$TMP" "$HOST:/tmp/scout-deploy.tar.gz"
sshpass -p "$PASS" scp -o StrictHostKeyChecking=no "$(dirname "$0")/deploy-scout.sh" "$HOST:/tmp/deploy-scout.sh"

sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no "$HOST" bash -s <<'REMOTE'
set -euo pipefail
PASS="maddy123"
mkdir -p /tmp/scout-deploy
tar -xzf /tmp/scout-deploy.tar.gz -C /tmp/scout-deploy
bash /tmp/deploy-scout.sh
echo "$PASS" | sudo -S systemctl restart sentinel-scout
sleep 2
systemctl is-active sentinel-scout
REMOTE
