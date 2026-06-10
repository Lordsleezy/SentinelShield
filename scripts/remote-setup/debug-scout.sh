#!/usr/bin/env bash
set -euo pipefail
PASS="maddy123"
sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no sentinel@192.168.0.117 'bash -s' <<'REMOTE'
echo "=== Scout service ==="
systemctl is-active sentinel-scout
grep SERPER /opt/sentinel/scout/.env | sed 's/=.*/=***/'

echo ""
echo "=== Direct Serper curl ==="
KEY=$(grep '^SERPER_API_KEY=' /opt/sentinel/scout/.env | cut -d= -f2-)
HTTP=$(curl -s -o /tmp/serper_resp.json -w "%{http_code}" -X POST "https://google.serper.dev/shopping" \
  -H "X-API-KEY: $KEY" \
  -H "Content-Type: application/json" \
  -d '{"q":"used gaming laptop","num":5}')
echo "HTTP $HTTP"
python3 -c "import json; d=json.load(open('/tmp/serper_resp.json')); print('shopping count:', len(d.get('shopping',[]))); print('keys:', list(d.keys())[:8]); print('first title:', (d.get('shopping') or [{}])[0].get('title','none'))"

echo ""
echo "=== Scout search test ==="
curl -s -X POST http://localhost:8001/search \
  -H "Content-Type: application/json" \
  -d '{"query":"used gaming laptop","max_results":5}' | python3 -m json.tool | head -40

echo ""
echo "=== Recent scout logs ==="
tail -40 /opt/sentinel/logs/scout.log 2>/dev/null || journalctl -u sentinel-scout -n 30 --no-pager
REMOTE
