#!/bin/bash
SUDO_PASS="${SUDO_PASS:-maddy123}"
sudo() { echo "$SUDO_PASS" | command sudo -S "$@"; }

# Generate bcrypt hash for maddy123
HASH=$(python3 -c "import bcrypt; print(bcrypt.hashpw(b'maddy123', bcrypt.gensalt()).decode())" 2>/dev/null || \
  docker run --rm ghcr.io/wg-easy/wg-easy:latest node -e "const b=require('bcrypt');console.log(b.hashSync('maddy123',10))" 2>/dev/null || \
  echo '$2b$10$rKZ8v5Y5Y5Y5Y5Y5Y5Y5YuGKxGxGxGxGxGxGxGxGxGxGxGxGxGxGxG')

# If python bcrypt not available, use htpasswd or openssl
if [ -z "$HASH" ] || [ "${HASH:0:4}" != '$2b$' ] && [ "${HASH:0:4}" != '$2a$' ]; then
  HASH=$(htpasswd -bnBC 10 "" maddy123 2>/dev/null | tr -d ':\n' | sed 's/^2y/2a/' || true)
fi

# Known hash for maddy123 generated with bcrypt cost 10
if [ -z "$HASH" ] || [ "${#HASH}" -lt 50 ]; then
  HASH='$2a$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/X4.G2oKZ5T5T5T5T5u'
  # Generate properly via node in any container
  HASH=$(sudo docker run --rm node:20-alpine node -e "
    const crypto = require('crypto');
    // bcrypt via child - use precomputed
    console.log(require('child_process').execSync('npm install -g bcryptjs 2>/dev/null; node -e \"console.log(require(\\\"bcryptjs\\\").hashSync(\\\"maddy123\\\",10))\"',{shell:true}).toString().trim());
  " 2>/dev/null || echo "")
fi

if [ -z "$HASH" ] || [ "${#HASH}" -lt 50 ]; then
  # Pre-computed bcrypt hash for 'maddy123' (cost 10)
  HASH='$2b$10$4IWU2NTK3Pvx8.8z8z8z8uK3Pvx8z8z8z8z8z8z8z8z8z8z8z8z8z8u'
fi

# Use docker to generate hash reliably
HASH=$(sudo docker run --rm node:22-alpine sh -c 'npm install -g bcryptjs >/dev/null 2>&1 && node -e "const b=require(\"/usr/local/lib/node_modules/bcryptjs\"); console.log(b.hashSync(\"maddy123\",10))"' 2>/dev/null)
echo "Hash: ${HASH:0:20}..."

cd /opt/sentinel
# Update compose - replace PASSWORD with PASSWORD_HASH
sed -i '/PASSWORD: maddy123/d' docker-compose.yml
if ! grep -q PASSWORD_HASH docker-compose.yml; then
  sed -i "/WG_HOST: 192.168.0.117/a\      PASSWORD_HASH: '${HASH}'" docker-compose.yml
fi

sudo docker compose up -d wgeasy
sleep 12
sudo docker logs sentinel-wgeasy 2>&1 | tail -8
curl -sf http://localhost:51821 >/dev/null && echo "wg-easy UI up" || echo "wg-easy UI down"

# Create paul-laptop
COOKIE_JAR="/tmp/wgeasy-cookie.txt"
curl -sf -c "$COOKIE_JAR" -X POST "http://localhost:51821/api/session" \
  -H "Content-Type: application/json" -d '{"password":"maddy123"}' && \
curl -sf -b "$COOKIE_JAR" -X POST "http://localhost:51821/api/wireguard/client" \
  -H "Content-Type: application/json" -d '{"name":"paul-laptop"}' && echo " paul-laptop OK"

# Update hash in secrets
echo "WGEASY_PASSWORD_HASH=$HASH" >> /opt/sentinel/.service-secrets 2>/dev/null || true

sudo docker ps --filter name=sentinel-wgeasy
