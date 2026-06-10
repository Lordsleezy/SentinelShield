#!/usr/bin/env bash
set -euo pipefail
PASS="maddy123"
sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no sentinel@192.168.0.117 'bash -s' <<'REMOTE'
KEY=$(grep '^SERPER_API_KEY=' /opt/sentinel/lister/.env | cut -d= -f2-)
curl -s -X POST "https://google.serper.dev/shopping" \
  -H "X-API-KEY: $KEY" \
  -H "Content-Type: application/json" \
  -d '{"q":"used ThinkPad X1 Carbon","num":3}' | python3 -m json.tool | head -80
REMOTE
