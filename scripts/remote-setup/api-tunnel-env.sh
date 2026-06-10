#!/bin/bash
set -euo pipefail

SUDO_PASS="${SUDO_PASS:-maddy123}"

sudo() { echo "$SUDO_PASS" | command sudo -S "$@"; }

log() { echo ">>> $*"; }
REPORT="/tmp/sentinel-final-report.txt"
: > "$REPORT"
report() { echo "$*" | tee -a "$REPORT"; }

MEDUSA_URL="http://localhost:9000"
ADMIN_EMAIL="admin@sentinelprime.org"
ADMIN_PASS="maddy123"

# ============================================================
# 3. API KEY
# ============================================================
log "3. Generating Medusa API key"

# Login to get JWT (Medusa v2)
LOGIN_RESP=$(curl -sf -X POST "$MEDUSA_URL/auth/user/emailpass" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$ADMIN_EMAIL\",\"password\":\"$ADMIN_PASS\"}" 2>&1 || echo "")

TOKEN=$(echo "$LOGIN_RESP" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('token','') or d.get('access_token',''))
except: print('')
" 2>/dev/null)

log "Login response: ${LOGIN_RESP:0:80}..."
log "Token obtained: ${TOKEN:0:30}..."

API_RESP=$(curl -sf -X POST "$MEDUSA_URL/admin/api-keys" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"title":"Sentinel Server Key","type":"secret"}' 2>&1 || echo "")

MEDUSA_API_KEY=$(echo "$API_RESP" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    ak = d.get('api_key', d)
    print(ak.get('token', ''))
except: print('')
" 2>/dev/null)

if [ -z "$MEDUSA_API_KEY" ]; then
  log "curl API key failed: $API_RESP — trying medusa CLI..."
  cd /opt/sentinel/medusa/apps/backend
  MEDUSA_API_KEY=$(/usr/bin/npx medusa exec "
    const { createApiKeysWorkflow } = require('@medusajs/medusa/core-flows');
    module.exports = async ({ container }) => {
      const { result } = await createApiKeysWorkflow(container).run({
        input: { api_keys: [{ title: 'Sentinel Server Key', type: 'secret', created_by: '' }] }
      });
      console.log(result[0].token);
    };
  " 2>/dev/null | tail -1 || echo "")
fi

sudo mkdir -p /opt/sentinel
sudo chown sentinel:sentinel /opt/sentinel

cat > /opt/sentinel/.env.shared << ENVEOF
MEDUSA_API_KEY=$MEDUSA_API_KEY
MEDUSA_API_URL=$MEDUSA_URL
ENVEOF
chmod 600 /opt/sentinel/.env.shared

# ============================================================
# 4. UPDATE ENV FILES
# ============================================================
log "4. Updating scout and lister .env files"

update_env() {
  local dir="$1"
  local envfile="$dir/.env"
  touch "$envfile"
  grep -q '^MEDUSA_API_URL=' "$envfile" 2>/dev/null && \
    sed -i "s|^MEDUSA_API_URL=.*|MEDUSA_API_URL=$MEDUSA_URL|" "$envfile" || \
    echo "MEDUSA_API_URL=$MEDUSA_URL" >> "$envfile"
  grep -q '^MEDUSA_API_KEY=' "$envfile" 2>/dev/null && \
    sed -i "s|^MEDUSA_API_KEY=.*|MEDUSA_API_KEY=$MEDUSA_API_KEY|" "$envfile" || \
    echo "MEDUSA_API_KEY=$MEDUSA_API_KEY" >> "$envfile"
  grep -q '^OLLAMA_HOST=' "$envfile" 2>/dev/null || \
    echo "OLLAMA_HOST=http://localhost:11434" >> "$envfile"
  grep -q '^SERPER_API_KEY=' "$envfile" 2>/dev/null || \
    echo "SERPER_API_KEY=" >> "$envfile"
}

update_env /opt/sentinel/scout
update_env /opt/sentinel/lister

# ============================================================
# 5. CLOUDFLARE TUNNEL
# ============================================================
log "5. Cloudflare tunnel setup"

TUNNEL_ID="bc6619f8-db74-488e-9a4f-6f063f71d78e"
CREDS="/home/sentinel/.cloudflared/${TUNNEL_ID}.json"
CONFIG="/home/sentinel/.cloudflared/config.yml"

mkdir -p /home/sentinel/.cloudflared

cat > "$CONFIG" << CFEOF
tunnel: $TUNNEL_ID
credentials-file: $CREDS

ingress:
  - hostname: legion.sentinelprime.org
    service: http://localhost:9000
  - hostname: scout.sentinelprime.org
    service: http://localhost:8001
  - hostname: lister.sentinelprime.org
    service: http://localhost:8002
  - service: http_status:404
CFEOF

cat > /tmp/sentinel-cloudflared.service << 'CFEOF'
[Unit]
Description=Sentinel Cloudflare Tunnel
After=network.target sentinel-medusa.service
Wants=network-online.target

[Service]
Type=simple
User=sentinel
Group=sentinel
ExecStart=/usr/bin/cloudflared tunnel --config /home/sentinel/.cloudflared/config.yml run
Restart=on-failure
RestartSec=10
StandardOutput=append:/opt/sentinel/logs/cloudflared.log
StandardError=append:/opt/sentinel/logs/cloudflared.log

[Install]
WantedBy=multi-user.target
CFEOF
sudo cp /tmp/sentinel-cloudflared.service /etc/systemd/system/sentinel-cloudflared.service

sudo systemctl daemon-reload
sudo systemctl enable sentinel-cloudflared
sudo systemctl restart sentinel-cloudflared

sleep 3

# ============================================================
# 6. FINAL REPORT
# ============================================================
log "6. Final report"

report ""
report "========================================"
report "         SENTINEL FINAL REPORT"
report "========================================"

report ""
report "--- PostgreSQL ---"
report "Version: $(psql --version)"
report "Service: $(systemctl is-active postgresql) / $(systemctl is-enabled postgresql)"
sudo -u postgres psql -c "\l sentinel_market" 2>/dev/null | tee -a "$REPORT" || true

report ""
report "--- Medusa ---"
if [ -f /opt/sentinel/medusa/package.json ]; then
  MEDUSA_VER=$(node -e "const p=require('/opt/sentinel/medusa/package.json'); console.log(p.dependencies?.['@medusajs/medusa']||p.devDependencies?.['@medusajs/medusa']||'see package.json')" 2>/dev/null)
  report "Version: $MEDUSA_VER"
fi
report "Service: $(systemctl is-active sentinel-medusa) / $(systemctl is-enabled sentinel-medusa)"
report "Admin URL: http://localhost:9000/app"
report "Public URL: https://legion.sentinelprime.org/app"
curl -sf "$MEDUSA_URL/health" >/dev/null && report "Health: OK" || report "Health: FAILED"

report ""
report "--- Cloudflare Tunnel ---"
report "Service: $(systemctl is-active sentinel-cloudflared) / $(systemctl is-enabled sentinel-cloudflared)"
report "Tunnel ID: $TUNNEL_ID"
report "Routes:"
report "  legion.sentinelprime.org  -> http://localhost:9000 (Medusa)"
report "  scout.sentinelprime.org   -> http://localhost:8001 (Scout)"
report "  lister.sentinelprime.org  -> http://localhost:8002 (Lister)"
cloudflared tunnel info "$TUNNEL_ID" 2>/dev/null | tee -a "$REPORT" || true

report ""
report "--- /opt/sentinel/.env.shared ---"
cat /opt/sentinel/.env.shared | tee -a "$REPORT"

report ""
report "--- /opt/sentinel/scout/.env ---"
cat /opt/sentinel/scout/.env | tee -a "$REPORT"

report ""
report "--- /opt/sentinel/lister/.env ---"
cat /opt/sentinel/lister/.env | tee -a "$REPORT"

report ""
report "--- Systemd Services ---"
for svc in ollama sentinel-scout sentinel-lister sentinel-medusa sentinel-cloudflared; do
  ENABLED=$(systemctl is-enabled "$svc" 2>/dev/null || echo "not-found")
  ACTIVE=$(systemctl is-active "$svc" 2>/dev/null || echo "not-found")
  report "  $svc: enabled=$ENABLED active=$ACTIVE"
done

report ""
report "=== REPORT COMPLETE ==="
cat "$REPORT"
