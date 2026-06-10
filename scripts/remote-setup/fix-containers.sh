#!/bin/bash
SUDO_PASS="${SUDO_PASS:-maddy123}"
sudo() { echo "$SUDO_PASS" | command sudo -S "$@"; }

echo "=== Port 3001 ==="
sudo ss -tlnp | grep 3001 || echo "free"
sudo lsof -i :3001 2>/dev/null | head -5

# Kill whatever holds 3001 if not docker
PID=$(sudo ss -tlnp | grep 3001 | grep -oP 'pid=\K[0-9]+' | head -1)
if [ -n "$PID" ]; then
  echo "Killing PID $PID on 3001"
  sudo kill "$PID" 2>/dev/null || true
  sleep 2
fi

# Fix jellyfin - remove user restriction
cd /opt/sentinel
python3 << 'PYEOF'
import yaml, sys
# Simple sed approach instead
PYEOF

# Patch compose for jellyfin and wgeasy
sed -i '/user: "1000:1000"/d' docker-compose.yml
sed -i '/group_add:/,+2d' docker-compose.yml

# wg-easy needs privileged on some systems
if ! grep -q 'privileged: true' docker-compose.yml; then
  sed -i '/container_name: sentinel-wgeasy/a\    privileged: true' docker-compose.yml
fi

sudo docker compose up -d uptime-kuma 2>&1
sudo docker compose up -d jellyfin wgeasy 2>&1
sleep 15
sudo docker ps -a

# WireGuard client
sleep 5
COOKIE_JAR="/tmp/wgeasy-cookie.txt"
for i in 1 2 3 4 5; do
  curl -sf -c "$COOKIE_JAR" -X POST "http://localhost:51821/api/session" \
    -H "Content-Type: application/json" -d '{"password":"maddy123"}' && break
  sleep 5
done
curl -sf -b "$COOKIE_JAR" -X POST "http://localhost:51821/api/wireguard/client" \
  -H "Content-Type: application/json" -d '{"name":"paul-laptop"}' 2>&1 || true

# Point DNS to Pi-hole now it's running
printf "nameserver 127.0.0.1\nnameserver 8.8.8.8\n" | sudo cp /dev/stdin /etc/resolv.conf 2>/dev/null || \
  printf "nameserver 127.0.0.1\nnameserver 8.8.8.8\n" > /tmp/resolv.conf && sudo cp /tmp/resolv.conf /etc/resolv.conf

# Uptime Kuma monitors
if [ -f /opt/sentinel/scripts/setup-uptime-kuma.sh ]; then
  bash /opt/sentinel/scripts/setup-uptime-kuma.sh 2>&1 || true
else
  cat > /opt/sentinel/scripts/setup-uptime-kuma.sh << 'KUMAEOF'
#!/bin/bash
sleep 5
curl -sf -X POST "http://localhost:3001/setup" -H "Content-Type: application/json" -d '{"username":"admin","password":"maddy123"}' || true
python3 -c "
import sqlite3,os,time
db='/opt/sentinel/data/uptime-kuma/kuma.db'
for _ in range(20):
  if os.path.exists(db): break
  time.sleep(2)
if not os.path.exists(db): exit()
m=[('Medusa','http://localhost:9000'),('Scout','http://localhost:8001'),('Lister','http://localhost:8002'),('Ollama','http://localhost:11434'),('Cloudflare Legion','https://legion.sentinelprime.org')]
c=sqlite3.connect(db);cur=c.cursor()
cur.execute('SELECT name FROM monitor');ex={r[0] for r in cur.fetchall()}
for n,u in m:
  if n not in ex: cur.execute(\"INSERT INTO monitor (name,active,type,url,interval,retry_interval,maxretries,upside_down,created_date) VALUES (?,1,'http',?,60,60,3,0,datetime('now'))\",(n,u));print('added',n)
c.commit();c.close()
"
KUMAEOF
  chmod +x /opt/sentinel/scripts/setup-uptime-kuma.sh
  bash /opt/sentinel/scripts/setup-uptime-kuma.sh 2>&1 || true
fi

# Start SD if not running
if [ -f /tmp/install-sd.sh ] && ! systemctl is-active sentinel-stablediffusion >/dev/null 2>&1; then
  mkdir -p /opt/sentinel/scripts /opt/sentinel/logs
  cp /tmp/install-sd.sh /opt/sentinel/scripts/
  chmod +x /opt/sentinel/scripts/install-sd.sh
  pgrep -f install-sd || nohup bash /opt/sentinel/scripts/install-sd.sh >> /opt/sentinel/logs/sd-install.log 2>&1 &
fi

echo "=== HEALTH CHECKS ==="
for url in "http://localhost:8080/admin/" "http://localhost:51821" "http://localhost:8096" "http://localhost:8888" "http://localhost:3000" "http://localhost:3001"; do
  code=$(curl -sf -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "fail")
  echo "$url -> $code"
done
