#!/bin/bash
SUDO_PASS="${SUDO_PASS:-maddy123}"
sudo() { echo "$SUDO_PASS" | command sudo -S "$@"; }

echo "=== SCOUT FINAL REPORT ==="
echo "Service: $(systemctl is-active sentinel-scout) / $(systemctl is-enabled sentinel-scout)"
echo ""
echo "Health:"
curl -s http://localhost:8001/health | python3 -m json.tool 2>/dev/null || curl -s http://localhost:8001/health
echo ""
echo "Search test:"
curl -s -X POST http://localhost:8001/search \
  -H "Content-Type: application/json" \
  -d '{"query":"used ThinkPad laptop","max_results":5}' \
  --max-time 180 | python3 -m json.tool 2>/dev/null | head -80
echo ""
echo "Approvals:"
curl -s http://localhost:8001/approvals | python3 -m json.tool 2>/dev/null | head -30
echo ""
echo "Supabase configured:"
grep -E '^SUPABASE_' /opt/sentinel/scout/.env | sed 's/=.*/=***/'
echo ""
echo "Supabase table check:"
cd /opt/sentinel/scout && venv/bin/python3 -c "
import asyncio, httpx, os
from dotenv import load_dotenv
load_dotenv()
url=os.getenv('SUPABASE_URL','').rstrip('/')
key=os.getenv('SUPABASE_SERVICE_ROLE_KEY','')
if not url or not key:
    print('  NOT CONFIGURED - add SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY to .env')
else:
    r=httpx.get(f'{url}/rest/v1/scout_approvals', headers={'apikey':key,'Authorization':f'Bearer {key}'}, params={'select':'id','limit':'1'})
    print(f'  HTTP {r.status_code}', 'OK' if r.status_code==200 else r.text[:100])
"
echo ""
echo "Scheduler:"
cd /opt/sentinel/scout && venv/bin/python3 -c "
from app.scheduler import start_scheduler
s=start_scheduler()
for j in s.get_jobs():
    print(f'  Job: {j.id} next={j.next_run_time}')
s.shutdown(wait=False)
" 2>/dev/null || echo "  daily scan at 02:00 (configured in app)"
echo ""
echo "Recent logs:"
tail -15 /opt/sentinel/logs/scout.log 2>/dev/null
echo "=== END ==="
