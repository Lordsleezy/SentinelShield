#!/usr/bin/env bash
set -euo pipefail

HOST="sentinel@192.168.0.117"
PASS="maddy123"

sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no "$HOST" bash -s <<'REMOTE'
echo "========== LISTER FINAL REPORT =========="
echo ""
echo "--- Service Status ---"
systemctl status sentinel-lister --no-pager -l | head -20
echo ""
echo "--- Port 8002 ---"
ss -tlnp | grep 8002 || echo "Port 8002 not listening"
echo ""
echo "--- Health ---"
curl -s http://localhost:8002/health | python3 -m json.tool 2>/dev/null || curl -s http://localhost:8002/health
echo ""
echo "--- POST /list test (used ThinkPad X1 Carbon) ---"
curl -s -X POST http://localhost:8002/list \
  -H "Content-Type: application/json" \
  -d '{"input": "used ThinkPad X1 Carbon"}' \
  --max-time 180 | python3 -m json.tool 2>/dev/null | head -60
echo ""
echo "--- GET /drafts ---"
curl -s http://localhost:8002/drafts | python3 -m json.tool 2>/dev/null | head -30 || curl -s http://localhost:8002/drafts
echo ""
echo "--- Supabase config ---"
grep -E '^SUPABASE_' /opt/sentinel/lister/.env | sed 's/=.*/=***/'
echo ""
echo "--- Medusa config ---"
grep -E '^MEDUSA_' /opt/sentinel/lister/.env | sed 's/=.*/=***/'
echo ""
echo "--- Recent logs ---"
tail -30 /opt/sentinel/logs/lister.log 2>/dev/null || journalctl -u sentinel-lister -n 20 --no-pager
echo ""
echo "========================================="
REMOTE
