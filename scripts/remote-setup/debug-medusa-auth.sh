#!/usr/bin/env bash
set -euo pipefail
PASS="maddy123"
sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no sentinel@192.168.0.117 'bash -s' <<'REMOTE'
MEDUSA_URL="http://localhost:9000"
ADMIN_EMAIL="admin@sentinelprime.org"
ADMIN_PASS="maddy123"
KEY=$(grep '^MEDUSA_API_KEY=' /opt/sentinel/lister/.env | cut -d= -f2-)

echo "=== Login ==="
LOGIN=$(curl -s -X POST "$MEDUSA_URL/auth/user/emailpass" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$ADMIN_EMAIL\",\"password\":\"$ADMIN_PASS\"}")
echo "$LOGIN" | python3 -m json.tool 2>/dev/null | head -20

TOKEN=$(echo "$LOGIN" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('token',''))")

echo ""
echo "=== Admin products with JWT ==="
curl -s -o /tmp/medusa_resp.txt -w "HTTP %{http_code}\n" \
  -H "Authorization: Bearer $TOKEN" \
  "$MEDUSA_URL/admin/products?limit=1"
head -c 300 /tmp/medusa_resp.txt; echo

echo ""
echo "=== Admin products with API key ==="
curl -s -o /tmp/medusa_resp2.txt -w "HTTP %{http_code}\n" \
  -H "Authorization: Bearer $KEY" \
  "$MEDUSA_URL/admin/products?limit=1"
head -c 300 /tmp/medusa_resp2.txt; echo

echo ""
echo "=== List API keys (JWT) ==="
curl -s -H "Authorization: Bearer $TOKEN" "$MEDUSA_URL/admin/api-keys" | python3 -m json.tool 2>/dev/null | head -40
REMOTE
