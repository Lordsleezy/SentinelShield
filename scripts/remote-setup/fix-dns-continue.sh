#!/bin/bash
set -euo pipefail
SUDO_PASS="${SUDO_PASS:-maddy123}"
sudo() { echo "$SUDO_PASS" | command sudo -S "$@"; }
log() { echo ">>> $*"; }

# Use public DNS until Pi-hole is running
echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf >/dev/null
echo "nameserver 1.1.1.1" | sudo tee -a /etc/resolv.conf >/dev/null

# Fix docker daemon DNS if needed
sudo mkdir -p /etc/docker
if [ ! -f /etc/docker/daemon.json ]; then
  echo '{"dns": ["8.8.8.8", "1.1.1.1"]}' | sudo tee /etc/docker/daemon.json >/dev/null
  sudo systemctl restart docker
  sleep 3
fi

log "DNS fixed, pulling images..."
cd /opt/sentinel
sudo docker compose pull 2>&1 | tail -15
sudo docker compose up -d 2>&1
sleep 20
sudo docker ps

# Now start Pi-hole and switch DNS to localhost
log "Switching system DNS to Pi-hole..."
sleep 10
if curl -sf http://localhost:8080/admin/ >/dev/null 2>&1; then
  echo "nameserver 127.0.0.1" | sudo tee /etc/resolv.conf >/dev/null
  log "DNS now points to Pi-hole"
else
  log "Pi-hole not ready on 8080 yet, keeping 8.8.8.8 as fallback"
  echo -e "nameserver 127.0.0.1\nnameserver 8.8.8.8" | sudo tee /etc/resolv.conf >/dev/null
fi

# WireGuard client
COOKIE_JAR="/tmp/wgeasy-cookie.txt"
sleep 5
curl -sf -c "$COOKIE_JAR" -X POST "http://localhost:51821/api/session" \
  -H "Content-Type: application/json" -d '{"password":"maddy123"}' || true
curl -sf -b "$COOKIE_JAR" -X POST "http://localhost:51821/api/wireguard/client" \
  -H "Content-Type: application/json" -d '{"name":"paul-laptop"}' && log "Created paul-laptop client" || log "wg client may exist"

# Uptime Kuma setup
sudo mkdir -p /opt/sentinel/scripts
cat > /opt/sentinel/scripts/setup-uptime-kuma.sh << 'KUMAEOF'
#!/bin/bash
set -euo pipefail
KUMA_URL="http://localhost:3001"
for i in $(seq 1 30); do curl -sf "$KUMA_URL/" >/dev/null 2>&1 && break; sleep 2; done
curl -sf -X POST "$KUMA_URL/setup" -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"maddy123"}' >/dev/null 2>&1 || true
python3 << 'PYEOF'
import sqlite3, os, time
db = "/opt/sentinel/data/uptime-kuma/kuma.db"
for _ in range(30):
    if os.path.exists(db): break
    time.sleep(2)
if not os.path.exists(db):
    print("kuma db not ready"); exit(0)
monitors = [
    ("Medusa", "http://localhost:9000"),
    ("Scout", "http://localhost:8001"),
    ("Lister", "http://localhost:8002"),
    ("Ollama", "http://localhost:11434"),
    ("Cloudflare Legion", "https://legion.sentinelprime.org"),
]
conn = sqlite3.connect(db)
cur = conn.cursor()
try:
    cur.execute("SELECT name FROM monitor")
    existing = {r[0] for r in cur.fetchall()}
    for name, url in monitors:
        if name in existing: continue
        cur.execute(
            "INSERT INTO monitor (name, active, type, url, interval, retry_interval, maxretries, upside_down, created_date) VALUES (?,1,'http',?,60,60,3,0,datetime('now'))",
            (name, url))
        print("added:", name)
    conn.commit()
except Exception as e: print(e)
conn.close()
PYEOF
KUMAEOF
chmod +x /opt/sentinel/scripts/setup-uptime-kuma.sh
bash /opt/sentinel/scripts/setup-uptime-kuma.sh 2>&1

# Stable Diffusion background install
if [ ! -f /opt/sentinel/stablediffusion/webui.sh ]; then
  cp /tmp/install-sd.sh /opt/sentinel/scripts/install-sd.sh 2>/dev/null || true
  chmod +x /opt/sentinel/scripts/install-sd.sh 2>/dev/null || true
  if [ -f /opt/sentinel/scripts/install-sd.sh ]; then
    nohup bash /opt/sentinel/scripts/install-sd.sh >> /opt/sentinel/logs/sd-install.log 2>&1 &
    log "SD install started PID $!"
  fi
fi

log "=== REPORT ==="
echo "Docker: $(docker --version)"
echo "Compose: $(docker compose version 2>/dev/null || docker-compose --version)"
sudo docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo "SD service: $(systemctl is-active sentinel-stablediffusion 2>/dev/null || echo installing)"
echo "Disk: $(df -h / | tail -1)"
echo "RAM: $(free -h | grep Mem)"
echo "DONE"
