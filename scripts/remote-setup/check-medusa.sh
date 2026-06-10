#!/usr/bin/env bash
set -euo pipefail
PASS="maddy123"
sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no sentinel@192.168.0.117 'bash -s' <<'REMOTE'
KEY=$(grep '^MEDUSA_API_KEY=' /opt/sentinel/lister/.env | cut -d= -f2-)
URL=$(grep '^MEDUSA_API_URL=' /opt/sentinel/lister/.env | cut -d= -f2-)
echo "Key length: ${#KEY}"
echo "URL: $URL"
BASIC=$(echo -n "${KEY}:" | base64 -w0)
echo -n "Basic auth: "
curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Basic $BASIC" "$URL/admin/products?limit=1"
echo
echo -n "Bearer auth: "
curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $KEY" "$URL/admin/products?limit=1"
echo
echo -n "Basic publishable: "
curl -s -o /dev/null -w "%{http_code}" "$URL/health"
echo
REMOTE
