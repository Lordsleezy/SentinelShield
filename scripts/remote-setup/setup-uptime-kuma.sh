#!/bin/bash
# Setup Uptime Kuma admin and monitors via API
set -euo pipefail

KUMA_URL="http://localhost:3001"
ADMIN_USER="admin"
ADMIN_PASS="maddy123"

# Wait for Kuma
for i in $(seq 1 30); do
  curl -sf "$KUMA_URL/" >/dev/null 2>&1 && break
  sleep 2
done

# Check if setup needed
SETUP_NEEDED=$(curl -sf "$KUMA_URL/setup" 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('setup',True))" 2>/dev/null || echo "true")

if [ "$SETUP_NEEDED" = "True" ] || [ "$SETUP_NEEDED" = "true" ]; then
  curl -sf -X POST "$KUMA_URL/setup" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"$ADMIN_USER\",\"password\":\"$ADMIN_PASS\"}" >/dev/null 2>&1 || true
  echo "Created Uptime Kuma admin: $ADMIN_USER"
fi

# Login via socket.io workaround - use form login
TOKEN=$(curl -sf -c /tmp/kuma-cookie.txt -X POST "$KUMA_URL/login" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$ADMIN_USER\",\"password\":\"$ADMIN_PASS\"}" 2>/dev/null || echo "")

# Add monitors via REST (Uptime Kuma 1.x uses internal API)
# Use direct SQLite insert as fallback
DB="/opt/sentinel/data/uptime-kuma/kuma.db"
if [ -f "$DB" ]; then
  python3 << PYEOF
import sqlite3, json, time
db = "$DB"
monitors = [
    ("Medusa", "http://localhost:9000", "http"),
    ("Scout", "http://localhost:8001", "http"),
    ("Lister", "http://localhost:8002", "http"),
    ("Ollama", "http://localhost:11434", "http"),
    ("Cloudflare Legion", "https://legion.sentinelprime.org", "http"),
]
conn = sqlite3.connect(db)
cur = conn.cursor()
cur.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='monitor'")
if not cur.fetchone():
    print("monitor table not ready")
    conn.close()
    exit(0)
cur.execute("SELECT name FROM monitor")
existing = {r[0] for r in cur.fetchall()}
for name, url, mtype in monitors:
    if name in existing:
        print(f"exists: {name}")
        continue
    cur.execute("""
        INSERT INTO monitor (name, active, type, url, interval, retry_interval, maxretries, upside_down, created_date)
        VALUES (?, 1, ?, ?, 60, 60, 3, 0, datetime('now'))
    """, (name, mtype, url))
    print(f"added: {name}")
conn.commit()
conn.close()
PYEOF
fi

echo "Uptime Kuma monitors configured"
