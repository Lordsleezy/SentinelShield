#!/bin/bash
SUDO_PASS="${SUDO_PASS:-maddy123}"
sudo() { echo "$SUDO_PASS" | command sudo -S "$@"; }

# Generate bcrypt hash
HASH=$(sudo docker run --rm node:22-alpine sh -c 'npm install -g bcryptjs >/dev/null 2>&1 && node -pe "require(\"bcryptjs\").hashSync(\"maddy123\",10)"')
echo "Generated hash length: ${#HASH}"

cd /opt/sentinel

# Rewrite wgeasy section in compose
python3 << PYEOF
import re
hash_val = """$HASH"""
with open("docker-compose.yml") as f:
    content = f.read()
# Remove old PASSWORD or PASSWORD_HASH lines
content = re.sub(r'      PASSWORD:.*\n', '', content)
content = re.sub(r'      PASSWORD_HASH:.*\n', '', content)
# Insert PASSWORD_HASH after WG_HOST line
content = content.replace(
    '      WG_HOST: 192.168.0.117\n',
    f'      WG_HOST: 192.168.0.117\n      PASSWORD_HASH: "{hash_val}"\n'
)
with open("docker-compose.yml", "w") as f:
    f.write(content)
print("Updated docker-compose.yml")
PYEOF

grep -A3 WG_HOST docker-compose.yml

sudo docker compose up -d wgeasy --force-recreate
sleep 10

# Test login
HTTP=$(curl -sf -o /dev/null -w "%{http_code}" -X POST http://localhost:51821/api/session \
  -H "Content-Type: application/json" -d '{"password":"maddy123"}')
echo "Login HTTP: $HTTP"

COOKIE="/tmp/wgeasy-cookie.txt"
curl -sf -c "$COOKIE" -X POST "http://localhost:51821/api/session" \
  -H "Content-Type: application/json" -d '{"password":"maddy123"}' && echo " login ok"

curl -sf -b "$COOKIE" -X POST "http://localhost:51821/api/wireguard/client" \
  -H "Content-Type: application/json" -d '{"name":"paul-laptop"}' && echo " client created"

mkdir -p /opt/sentinel/data/wgeasy/clients
CLIENTS=$(curl -sf -b "$COOKIE" "http://localhost:51821/api/wireguard/client")
echo "$CLIENTS" | python3 -c "import sys,json; d=json.load(sys.stdin); print([c.get('name') for c in d])" 2>/dev/null

# Get config for paul-laptop
ID=$(echo "$CLIENTS" | python3 -c "
import sys,json
for c in json.load(sys.stdin):
    if c.get('name')=='paul-laptop': print(c['id']); break
" 2>/dev/null)
if [ -n "$ID" ]; then
  curl -sf -b "$COOKIE" "http://localhost:51821/api/wireguard/client/$ID/configuration" \
    > /opt/sentinel/data/wgeasy/clients/paul-laptop.conf
  echo "Config saved ($(wc -l < /opt/sentinel/data/wgeasy/clients/paul-laptop.conf) lines)"
  grep -E 'Endpoint|AllowedIPs' /opt/sentinel/data/wgeasy/clients/paul-laptop.conf
fi
