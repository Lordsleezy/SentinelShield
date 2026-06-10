#!/bin/bash
SUDO_PASS="${SUDO_PASS:-maddy123}"
sudo() { echo "$SUDO_PASS" | command sudo -S "$@"; }

# Create paul-laptop if missing
COOKIE_JAR="/tmp/wgeasy-cookie.txt"
curl -sf -c "$COOKIE_JAR" -X POST "http://localhost:51821/api/session" \
  -H "Content-Type: application/json" -d '{"password":"maddy123"}' >/dev/null 2>&1
curl -sf -b "$COOKIE_JAR" -X POST "http://localhost:51821/api/wireguard/client" \
  -H "Content-Type: application/json" -d '{"name":"paul-laptop"}' >/dev/null 2>&1 && echo "paul-laptop: created" || echo "paul-laptop: check UI"

echo "========================================"
echo "       SENTINEL SERVICES FINAL REPORT"
echo "========================================"
echo ""
echo "--- Docker ---"
docker --version
docker compose version 2>/dev/null || docker-compose --version
echo ""
echo "--- Running Containers ---"
sudo docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
echo ""
echo "--- Stable Diffusion ---"
echo "Service: $(systemctl is-active sentinel-stablediffusion 2>/dev/null || echo installing)"
if pgrep -f install-sd >/dev/null; then echo "Install: IN PROGRESS (see /opt/sentinel/logs/sd-install.log)"; fi
tail -3 /opt/sentinel/logs/sd-install.log 2>/dev/null
curl -sf -o /dev/null -w "Port 7860 HTTP: %{http_code}\n" http://localhost:7860 2>/dev/null || echo "Port 7860: not ready"
ls -lh /opt/sentinel/stablediffusion/models/Stable-diffusion/ 2>/dev/null | tail -3
echo ""
echo "--- Web UIs & Passwords ---"
echo "  Pi-hole:      http://192.168.0.117:8080/admin     password: maddy123"
echo "  WireGuard:    http://192.168.0.117:51821          password: maddy123"
echo "  Jellyfin:     http://192.168.0.117:8096           first-run wizard"
echo "  Nextcloud:    http://192.168.0.117:8888           admin / maddy123"
echo "  Open WebUI:   http://192.168.0.117:3000           no auth"
echo "  Stable Diff:  http://192.168.0.117:7860           no auth (--api)"
echo "  Uptime Kuma:  http://192.168.0.117:3001           admin / maddy123"
echo ""
echo "--- Uptime Kuma Monitors ---"
python3 -c "
import sqlite3,os
db='/opt/sentinel/data/uptime-kuma/kuma.db'
if os.path.exists(db):
 c=sqlite3.connect(db);r=c.execute('SELECT name,url FROM monitor').fetchall()
 for n,u in r: print(f'  {n}: {u}')
 c.close()
" 2>/dev/null
echo ""
echo "--- docker-compose.yml ---"
head -5 /opt/sentinel/docker-compose.yml
wc -l /opt/sentinel/docker-compose.yml
echo ""
echo "--- Disk & RAM ---"
df -h / | tail -1
free -h | grep Mem
echo "========================================"
