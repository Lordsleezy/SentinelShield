#!/usr/bin/env bash
set -euo pipefail

HOST="sentinel@192.168.0.117"
PASS="maddy123"
REMOTE_DIR="/opt/sentinel/lister"
LOCAL_DIR="$(cd "$(dirname "$0")/../../services/lister" && pwd)"

echo "=== Packaging Lister ==="
TMP="/tmp/lister-deploy.tar.gz"
tar -czf "$TMP" -C "$LOCAL_DIR" \
  app requirements.txt schema.sql .env.example

echo "=== Uploading to $HOST ==="
sshpass -p "$PASS" scp -o StrictHostKeyChecking=no "$TMP" "$HOST:/tmp/lister-deploy.tar.gz"

echo "=== Installing on remote ==="
sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no "$HOST" bash -s <<'REMOTE'
set -euo pipefail
PASS="maddy123"
REMOTE_DIR="/opt/sentinel/lister"

echo "$PASS" | sudo -S mkdir -p "$REMOTE_DIR"
echo "$PASS" | sudo -S tar -xzf /tmp/lister-deploy.tar.gz -C "$REMOTE_DIR"
echo "$PASS" | sudo -S chown -R sentinel:sentinel "$REMOTE_DIR"

# Preserve existing .env keys, merge from shared
if [ ! -f "$REMOTE_DIR/.env" ]; then
  cp /opt/sentinel/.env.shared "$REMOTE_DIR/.env" 2>/dev/null || touch "$REMOTE_DIR/.env"
fi
grep -q '^SUPABASE_URL=' "$REMOTE_DIR/.env" || echo 'SUPABASE_URL=' >> "$REMOTE_DIR/.env"
grep -q '^SUPABASE_SERVICE_ROLE_KEY=' "$REMOTE_DIR/.env" || echo 'SUPABASE_SERVICE_ROLE_KEY=' >> "$REMOTE_DIR/.env"
grep -q '^OLLAMA_MODEL=' "$REMOTE_DIR/.env" || echo 'OLLAMA_MODEL=mistral' >> "$REMOTE_DIR/.env"
grep -q '^LOG_FILE=' "$REMOTE_DIR/.env" || echo 'LOG_FILE=/opt/sentinel/logs/lister.log' >> "$REMOTE_DIR/.env"
grep -q '^PORT=' "$REMOTE_DIR/.env" || echo 'PORT=8002' >> "$REMOTE_DIR/.env"

# Python venv
if [ ! -d "$REMOTE_DIR/venv" ]; then
  python3 -m venv "$REMOTE_DIR/venv"
fi
"$REMOTE_DIR/venv/bin/pip" install -q --upgrade pip
"$REMOTE_DIR/venv/bin/pip" install -q -r "$REMOTE_DIR/requirements.txt"
"$REMOTE_DIR/venv/bin/playwright" install chromium 2>/dev/null || true
"$REMOTE_DIR/venv/bin/crawl4ai-setup" 2>/dev/null || true

# Systemd service
echo "$PASS" | sudo -S tee /etc/systemd/system/sentinel-lister.service > /dev/null <<'UNIT'
[Unit]
Description=Sentinel Lister - AI Product Listing Builder
After=network.target ollama.service

[Service]
Type=simple
User=sentinel
WorkingDirectory=/opt/sentinel/lister
EnvironmentFile=/opt/sentinel/lister/.env
ExecStart=/opt/sentinel/lister/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8002
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT

echo "$PASS" | sudo -S systemctl daemon-reload
echo "$PASS" | sudo -S systemctl enable sentinel-lister
echo "$PASS" | sudo -S systemctl restart sentinel-lister
sleep 3
systemctl is-active sentinel-lister
REMOTE

echo "=== Deploy complete ==="
