#!/bin/bash
set -euo pipefail

SUDO_PASS="${SUDO_PASS:-maddy123}"
REPORT="/tmp/sentinel-services-report.txt"

sudo() { echo "$SUDO_PASS" | command sudo -S "$@"; }
log() { echo ">>> $*"; tee -a "$REPORT"; }

: > "$REPORT"
log "=== SENTINEL SERVICES INSTALL $(date) ==="

# ---- DOCKER ----
if ! command -v docker >/dev/null 2>&1; then
  log "Installing Docker via apt (docker.io)..."
  sudo apt-get update -qq
  sudo apt-get install -y -qq docker.io docker-compose-v2 containerd runc
fi
# Ensure compose plugin alias
if ! docker compose version >/dev/null 2>&1; then
  sudo ln -sf /usr/libexec/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose 2>/dev/null || true
fi
sudo usermod -aG docker sentinel 2>/dev/null || true
sudo systemctl enable docker
sudo systemctl start docker
log "Docker: $(docker --version)"
log "Compose: $(docker compose version)"

# ---- DIRS ----
sudo mkdir -p /opt/sentinel/{media/movies,media/tv,data/pihole,data/pihole-dnsmasq,data/wgeasy,data/jellyfin,data/jellyfin-cache,data/nextcloud,data/open-webui,data/uptime-kuma,logs}
sudo chown -R sentinel:sentinel /opt/sentinel

# Free port 53 for Pi-hole
if systemctl is-active systemd-resolved >/dev/null 2>&1; then
  log "Disabling systemd-resolved (Pi-hole will take over DNS after start)"
  sudo systemctl stop systemd-resolved
  sudo systemctl disable systemd-resolved
  sudo rm -f /etc/resolv.conf
  # Use public DNS until Pi-hole container is running
  printf "nameserver 8.8.8.8\nnameserver 1.1.1.1\n" | sudo tee /etc/resolv.conf >/dev/null
fi
sudo mkdir -p /etc/docker
echo '{"dns": ["8.8.8.8", "1.1.1.1"]}' | sudo tee /etc/docker/daemon.json >/dev/null
sudo systemctl restart docker 2>/dev/null || true

# ---- DOCKER COMPOSE ----
log "Writing docker-compose.yml"
cat > /opt/sentinel/docker-compose.yml << 'EOF'
services:
  pihole:
    image: pihole/pihole:latest
    container_name: sentinel-pihole
    hostname: sentinel-pihole
    environment:
      TZ: America/Los_Angeles
      WEBPASSWORD: maddy123
      FTLCONF_LOCAL_IPV4: 192.168.0.117
      FTLCONF_webserver_port: "8080"
      DNSMASQ_LISTENING: all
    volumes:
      - /opt/sentinel/data/pihole/etc:/etc/pihole
      - /opt/sentinel/data/pihole-dnsmasq:/etc/dnsmasq.d
    ports:
      - "8080:8080"
      - "53:53/tcp"
      - "53:53/udp"
    cap_add:
      - NET_ADMIN
    restart: unless-stopped

  wgeasy:
    image: ghcr.io/wg-easy/wg-easy:latest
    container_name: sentinel-wgeasy
    environment:
      LANG: en
      WG_HOST: 192.168.0.117
      PASSWORD: maddy123
      PORT: 51821
      WG_PORT: 51820
      WG_DEFAULT_DNS: 192.168.0.117
      WG_ALLOWED_IPS: 0.0.0.0/0, ::/0
    volumes:
      - /opt/sentinel/data/wgeasy:/etc/wireguard
    ports:
      - "51820:51820/udp"
      - "51821:51821/tcp"
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    sysctls:
      - net.ipv4.ip_forward=1
      - net.ipv4.conf.all.src_valid_mark=1
    restart: unless-stopped

  jellyfin:
    image: jellyfin/jellyfin:latest
    container_name: sentinel-jellyfin
    user: "1000:1000"
    environment:
      JELLYFIN_PublishedServerUrl: http://192.168.0.117:8096
    volumes:
      - /opt/sentinel/data/jellyfin/config:/config
      - /opt/sentinel/data/jellyfin-cache:/cache
      - /opt/sentinel/media/movies:/media/movies:ro
      - /opt/sentinel/media/tv:/media/tv:ro
    ports:
      - "8096:8096"
    restart: unless-stopped

  nextcloud:
    image: nextcloud:latest
    container_name: sentinel-nextcloud
    environment:
      SQLITE_DATABASE: nextcloud
      NEXTCLOUD_ADMIN_USER: admin
      NEXTCLOUD_ADMIN_PASSWORD: maddy123
      NEXTCLOUD_TRUSTED_DOMAINS: 192.168.0.117 localhost
    volumes:
      - /opt/sentinel/data/nextcloud:/var/www/html
    ports:
      - "8888:80"
    restart: unless-stopped

  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: sentinel-open-webui
    environment:
      OLLAMA_BASE_URL: http://host.docker.internal:11434
      WEBUI_AUTH: "false"
      ENABLE_SIGNUP: "false"
      ANONYMOUS_USER_ACCESS: "true"
    extra_hosts:
      - "host.docker.internal:host-gateway"
    volumes:
      - /opt/sentinel/data/open-webui:/app/backend/data
    ports:
      - "3000:8080"
    restart: unless-stopped

  uptime-kuma:
    image: louislam/uptime-kuma:1
    container_name: sentinel-uptime-kuma
    volumes:
      - /opt/sentinel/data/uptime-kuma:/app/data
    ports:
      - "3001:3001"
    restart: unless-stopped
EOF

log "Pulling images..."
cd /opt/sentinel
sudo docker compose pull 2>&1 | tail -8

log "Starting containers..."
sudo docker compose up -d 2>&1
sleep 15
sudo docker ps

# ---- WIREGUARD CLIENT paul-laptop ----
log "Creating WireGuard client paul-laptop via wg-easy API..."
sleep 5
COOKIE_JAR="/tmp/wgeasy-cookie.txt"
rm -f "$COOKIE_JAR"
# wg-easy v14+ uses POST /api/session
LOGIN=$(curl -sf -c "$COOKIE_JAR" -X POST "http://localhost:51821/api/session" \
  -H "Content-Type: application/json" \
  -d '{"password":"maddy123"}' 2>&1 || echo "fail")
log "wg-easy login: ${LOGIN:0:50}"

CLIENT=$(curl -sf -b "$COOKIE_JAR" -X POST "http://localhost:51821/api/wireguard/client" \
  -H "Content-Type: application/json" \
  -d '{"name":"paul-laptop"}' 2>&1 || echo "fail")
log "wg-easy client: ${CLIENT:0:100}"

# Save client config if available
curl -sf -b "$COOKIE_JAR" "http://localhost:51821/api/wireguard/client" 2>/dev/null | \
  python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    for c in (d if isinstance(d,list) else d.get('clients',[])):
        if c.get('name')=='paul-laptop':
            print('Client ID:', c.get('id','?'))
except: pass
" 2>/dev/null || true

mkdir -p /opt/sentinel/data/wgeasy/clients
curl -sf -b "$COOKIE_JAR" "http://localhost:51821/api/wireguard/client" > /opt/sentinel/data/wgeasy/clients/clients.json 2>/dev/null || true

log "=== STABLE DIFFUSION (background install) ==="
if [ -f /tmp/install-sd.sh ] || [ -f /opt/sentinel/scripts/install-sd.sh ]; then
  cp /tmp/install-sd.sh /opt/sentinel/scripts/install-sd.sh 2>/dev/null || true
  chmod +x /opt/sentinel/scripts/install-sd.sh
  nohup bash /opt/sentinel/scripts/install-sd.sh > /opt/sentinel/logs/sd-install.log 2>&1 &
  log "SD install started in background (PID $!) — see /opt/sentinel/logs/sd-install.log"
else
  log "WARN: install-sd.sh not found, skipping SD"
fi

log "=== UPTIME KUMA SETUP ==="
sleep 10
# Initialize Uptime Kuma with default admin if not set up
python3 << 'PYEOF'
import sqlite3, os, json, hashlib, secrets

db = "/opt/sentinel/data/uptime-kuma/kuma.db"
if not os.path.exists(db):
    print("Kuma DB not ready yet - monitors added after first-start")
    exit(0)

conn = sqlite3.connect(db)
cur = conn.cursor()
try:
    cur.execute("SELECT COUNT(*) FROM user")
    users = cur.fetchone()[0]
    print(f"Uptime Kuma users: {users}")
except Exception as e:
    print(f"Kuma not initialized: {e}")
conn.close()
PYEOF

# Setup Uptime Kuma monitors
sudo mkdir -p /opt/sentinel/scripts
cat > /opt/sentinel/scripts/setup-uptime-kuma.sh << 'KUMAEOF'
#!/bin/bash
set -euo pipefail
KUMA_URL="http://localhost:3001"
ADMIN_USER="admin"
ADMIN_PASS="maddy123"
for i in $(seq 1 30); do curl -sf "$KUMA_URL/" >/dev/null 2>&1 && break; sleep 2; done
curl -sf -X POST "$KUMA_URL/setup" -H "Content-Type: application/json" \
  -d "{\"username\":\"$ADMIN_USER\",\"password\":\"$ADMIN_PASS\"}" >/dev/null 2>&1 || true
DB="/opt/sentinel/data/uptime-kuma/kuma.db"
python3 << PYEOF
import sqlite3, os
db = "/opt/sentinel/data/uptime-kuma/kuma.db"
if not os.path.exists(db): exit(0)
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
        cur.execute("INSERT INTO monitor (name, active, type, url, interval, retry_interval, maxretries, upside_down, created_date) VALUES (?,1,'http',?,60,60,3,0,datetime('now'))", (name, url))
        print("added:", name)
    conn.commit()
except Exception as e: print(e)
conn.close()
PYEOF
KUMAEOF
chmod +x /opt/sentinel/scripts/setup-uptime-kuma.sh
sleep 5
bash /opt/sentinel/scripts/setup-uptime-kuma.sh 2>&1 | tee -a "$REPORT" || log "Uptime Kuma setup deferred"

log "=== FINAL REPORT ==="
log "Docker: $(docker --version)"
log "Compose: $(docker compose version)"
echo "" | tee -a "$REPORT"
sudo docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | tee -a "$REPORT"
echo "" | tee -a "$REPORT"
log "Stable Diffusion: $(systemctl is-active sentinel-stablediffusion)"
log "SD port check: $(curl -sf -o /dev/null -w '%{http_code}' http://localhost:7860 2>/dev/null || echo pending)"
echo "" | tee -a "$REPORT"
log "URLS & PASSWORDS:"
log "  Pi-hole:      http://192.168.0.117:8080/admin     password: maddy123"
log "  WireGuard:    http://192.168.0.117:51821          password: maddy123"
log "  Jellyfin:     http://192.168.0.117:8096           first-run setup"
log "  Nextcloud:    http://192.168.0.117:8888           admin / maddy123"
log "  Open WebUI:   http://192.168.0.117:3000           no auth"
log "  Stable Diff:  http://192.168.0.117:7860           no auth, --api enabled"
log "  Uptime Kuma:  http://192.168.0.117:3001           admin / maddy123"
echo "" | tee -a "$REPORT"
log "Disk: $(df -h / | tail -1)"
log "RAM:  $(free -h | grep Mem)"
log "=== DONE ==="
cat "$REPORT"
