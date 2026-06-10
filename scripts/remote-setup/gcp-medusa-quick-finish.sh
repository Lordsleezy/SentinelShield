#!/usr/bin/env bash
set -euo pipefail
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
nvm use 20 >/dev/null

MEDUSA_SRC="$HOME/medusa-build"
MEDUSA_ROOT="/opt/medusa"
DB_URL="postgresql://sentinel:maddy123@localhost:5432/sentinel_market"

# Move into /opt/medusa without deleting the directory (can't rm dir under /opt)
mkdir -p "$MEDUSA_ROOT/logs"
shopt -s dotglob
cp -a "$MEDUSA_SRC"/* "$MEDUSA_ROOT"/
shopt -u dotglob

if [ -f "$MEDUSA_ROOT/apps/backend/package.json" ]; then
  MEDUSA_DIR="$MEDUSA_ROOT/apps/backend"
else
  MEDUSA_DIR="$MEDUSA_ROOT"
fi

cd "$MEDUSA_DIR"
grep -q '^MEDUSA_API_URL=' .env 2>/dev/null || echo "MEDUSA_API_URL=http://localhost:9000" >> .env
grep -q '^MEDUSA_API_KEY=' .env 2>/dev/null || echo "MEDUSA_API_KEY=" >> .env

npx medusa user --email admin@sentinelprime.org --password maddy123 2>&1 || true

NODE_PATH=$(dirname "$(which node)")
NPX_BIN=$(which npx)
mkdir -p "$HOME/.config/systemd/user"

cat > "$HOME/.config/systemd/user/sentinel-medusa.service" << EOF
[Unit]
Description=Sentinel Medusa v2
After=network.target

[Service]
WorkingDirectory=$MEDUSA_DIR
EnvironmentFile=$MEDUSA_DIR/.env
Environment=PATH=$NODE_PATH:/usr/bin:/bin
ExecStart=$NPX_BIN medusa develop
Restart=on-failure
RestartSec=10
StandardOutput=append:$MEDUSA_ROOT/logs/medusa.log
StandardError=append:$MEDUSA_ROOT/logs/medusa.log

[Install]
WantedBy=default.target
EOF

loginctl enable-linger pgg124 2>/dev/null || true
systemctl --user daemon-reload
systemctl --user enable sentinel-medusa
systemctl --user restart sentinel-medusa

for i in $(seq 1 40); do
  curl -sf http://localhost:9000/health >/dev/null && break
  sleep 5
done

TOKEN=$(curl -sf -X POST http://localhost:9000/auth/user/emailpass \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@sentinelprime.org","password":"maddy123"}' | \
  python3 -c "import sys,json; print(json.load(sys.stdin).get('token',''))" 2>/dev/null || echo "")

if [ -n "$TOKEN" ]; then
  KEY=$(curl -sf -X POST http://localhost:9000/admin/api-keys \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"title":"Sentinel Server Key","type":"secret"}' | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('api_key',d).get('token',''))" 2>/dev/null || echo "")
  if [ -n "$KEY" ]; then
    sed -i "s|^MEDUSA_API_KEY=.*|MEDUSA_API_KEY=$KEY|" "$MEDUSA_DIR/.env"
  fi
fi

echo "=== DONE ==="
echo "Medusa dir: $MEDUSA_DIR"
echo "Service: $(systemctl --user is-active sentinel-medusa)"
curl -sf http://localhost:9000/health && echo "Health OK" || echo "Health FAILED"
grep MEDUSA_API "$MEDUSA_DIR/.env" | sed 's/KEY=.*/KEY=***/'
