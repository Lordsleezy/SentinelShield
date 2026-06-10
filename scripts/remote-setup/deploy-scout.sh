#!/bin/bash
set -euo pipefail
SUDO_PASS="${SUDO_PASS:-maddy123}"
sudo() { echo "$SUDO_PASS" | command sudo -S "$@"; }

SCOUT_DIR="/opt/sentinel/scout"
SRC="/tmp/scout-deploy"

log() { echo ">>> $*"; }

log "Deploying Scout to $SCOUT_DIR"

# Backup existing .env
if [ -f "$SCOUT_DIR/.env" ]; then
  cp "$SCOUT_DIR/.env" /tmp/scout.env.bak
fi

# Sync new code (uploaded to /tmp/scout-deploy)
sudo mkdir -p "$SCOUT_DIR"
sudo rm -rf "$SCOUT_DIR/app" "$SCOUT_DIR/main.py" 2>/dev/null || true
cp -r "$SRC"/* "$SCOUT_DIR/" 2>/dev/null || cp -r /tmp/scout-service/* "$SCOUT_DIR/"
sudo chown -R sentinel:sentinel "$SCOUT_DIR"

# Restore / merge .env
if [ -f /tmp/scout.env.bak ]; then
  cp /tmp/scout.env.bak "$SCOUT_DIR/.env"
fi
touch "$SCOUT_DIR/.env"
grep -q '^SUPABASE_URL=' "$SCOUT_DIR/.env" || echo "SUPABASE_URL=" >> "$SCOUT_DIR/.env"
grep -q '^SUPABASE_SERVICE_ROLE_KEY=' "$SCOUT_DIR/.env" || echo "SUPABASE_SERVICE_ROLE_KEY=" >> "$SCOUT_DIR/.env"
grep -q '^OLLAMA_MODEL=' "$SCOUT_DIR/.env" || echo "OLLAMA_MODEL=mistral" >> "$SCOUT_DIR/.env"
grep -q '^LISTER_URL=' "$SCOUT_DIR/.env" || echo "LISTER_URL=http://localhost:8002" >> "$SCOUT_DIR/.env"

cd "$SCOUT_DIR"

# Python venv
if [ ! -d venv ]; then
  python3 -m venv venv
fi
venv/bin/pip install --upgrade pip
venv/bin/pip install -r requirements.txt
venv/bin/playwright install chromium
venv/bin/playwright install-deps chromium 2>/dev/null || sudo venv/bin/playwright install-deps chromium

# Systemd
cat > /tmp/sentinel-scout.service << 'EOF'
[Unit]
Description=Sentinel Scout - Deal finding FastAPI service
After=network.target ollama.service
Wants=ollama.service

[Service]
Type=simple
User=sentinel
Group=sentinel
WorkingDirectory=/opt/sentinel/scout
EnvironmentFile=/opt/sentinel/scout/.env
ExecStart=/opt/sentinel/scout/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8001
Restart=on-failure
RestartSec=10
StandardOutput=append:/opt/sentinel/logs/scout.log
StandardError=append:/opt/sentinel/logs/scout.log

[Install]
WantedBy=multi-user.target
EOF
sudo cp /tmp/sentinel-scout.service /etc/systemd/system/sentinel-scout.service
sudo mkdir -p /opt/sentinel/logs
sudo chown sentinel:sentinel /opt/sentinel/logs
sudo systemctl daemon-reload
sudo systemctl enable sentinel-scout
sudo systemctl restart sentinel-scout

sleep 5
log "Service: $(systemctl is-active sentinel-scout)"

# Health check
curl -sf http://localhost:8001/health && echo " health OK" || echo " health FAIL"

# Test search (may take a while with playwright)
log "Testing POST /search..."
curl -sf -X POST http://localhost:8001/search \
  -H "Content-Type: application/json" \
  -d '{"query":"used ThinkPad laptop","max_results":5}' \
  --max-time 180 | head -c 2000 || echo "search test timed out or failed"

echo ""
log "Deploy complete"
