#!/bin/bash
SUDO_PASS="${SUDO_PASS:-maddy123}"
sudo() { echo "$SUDO_PASS" | command sudo -S "$@"; }

echo "=== wg-easy logs ==="
sudo docker logs sentinel-wgeasy 2>&1 | tail -20

# Fix wg-easy - may need wireguard kernel module
sudo modprobe wireguard 2>/dev/null || sudo apt-get install -y -qq wireguard 2>/dev/null || true

# Reset wgeasy data if corrupted
if sudo docker logs sentinel-wgeasy 2>&1 | tail -5 | grep -qiE 'error|fail'; then
  sudo docker stop sentinel-wgeasy
  sudo rm -rf /opt/sentinel/data/wgeasy/*
  sudo docker start sentinel-wgeasy
  sleep 10
fi
sudo docker logs sentinel-wgeasy 2>&1 | tail -10

# Fix uptime kuma db permissions
sudo chown -R 1000:1000 /opt/sentinel/data/uptime-kuma 2>/dev/null || true
sudo chmod -R u+rwX /opt/sentinel/data/uptime-kuma 2>/dev/null || true

# Setup kuma via docker exec as correct user
sudo docker exec sentinel-uptime-kuma node -e "
const fs=require('fs');
console.log('kuma data ok');
" 2>/dev/null || true

curl -sf -X POST "http://localhost:3001/setup" \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"maddy123"}' 2>&1 | head -3

# Fix kuma db ownership inside container
sudo docker exec -u root sentinel-uptime-kuma chown -R node:node /app/data 2>/dev/null || true

python3 << 'PYEOF'
import sqlite3, os, time, subprocess
db = "/opt/sentinel/data/uptime-kuma/kuma.db"
if not os.path.exists(db):
    print("waiting for kuma db"); time.sleep(10)
if not os.path.exists(db):
    print("no db"); exit(0)
# fix perms
subprocess.run(["sudo","chmod","666",db], check=False)
monitors = [
    ("Medusa", "http://localhost:9000"),
    ("Scout", "http://localhost:8001"),
    ("Lister", "http://localhost:8002"),
    ("Ollama", "http://localhost:11434"),
    ("Cloudflare Legion", "https://legion.sentinelprime.org"),
]
conn = sqlite3.connect(db)
cur = conn.cursor()
cur.execute("SELECT name FROM monitor")
existing = {r[0] for r in cur.fetchall()}
for name, url in monitors:
    if name in existing:
        print("exists:", name)
        continue
    cur.execute(
        "INSERT INTO monitor (name, active, type, url, interval, retry_interval, maxretries, upside_down, created_date) VALUES (?,1,'http',?,60,60,3,0,datetime('now'))",
        (name, url))
    print("added:", name)
conn.commit()
conn.close()
PYEOF

# wg-easy client
sleep 5
COOKIE_JAR="/tmp/wgeasy-cookie.txt"
if curl -sf -c "$COOKIE_JAR" -X POST "http://localhost:51821/api/session" \
  -H "Content-Type: application/json" -d '{"password":"maddy123"}'; then
  curl -sf -b "$COOKIE_JAR" -X POST "http://localhost:51821/api/wireguard/client" \
    -H "Content-Type: application/json" -d '{"name":"paul-laptop"}' && echo "paul-laptop created"
fi

# SD status
echo "=== SD ==="
tail -5 /opt/sentinel/logs/sd-install.log 2>/dev/null || echo "no sd log"
systemctl is-active sentinel-stablediffusion 2>/dev/null || echo "sd inactive"
pgrep -af install-sd || echo "no sd install proc"

# Start SD if needed
if [ ! -f /opt/sentinel/stablediffusion/webui.sh ] && [ -f /tmp/install-sd.sh ]; then
  mkdir -p /opt/sentinel/scripts /opt/sentinel/logs
  cp /tmp/install-sd.sh /opt/sentinel/scripts/
  chmod +x /opt/sentinel/scripts/install-sd.sh
  nohup bash /opt/sentinel/scripts/install-sd.sh >> /opt/sentinel/logs/sd-install.log 2>&1 &
  echo "Started SD install"
elif [ -f /opt/sentinel/stablediffusion/webui.sh ] && ! systemctl is-active sentinel-stablediffusion >/dev/null 2>&1; then
  pgrep -f install-sd || (nohup bash /opt/sentinel/scripts/install-sd.sh >> /opt/sentinel/logs/sd-install.log 2>&1 &)
fi

echo "=== FINAL docker ps ==="
sudo docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo "=== DISK/RAM ==="
df -h / | tail -1
free -h | grep Mem
