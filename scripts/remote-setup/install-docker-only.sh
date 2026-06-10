#!/bin/bash
set -euo pipefail
SUDO_PASS="${SUDO_PASS:-maddy123}"
sudo() { echo "$SUDO_PASS" | command sudo -S "$@"; }
log() { echo ">>> $*"; }

# Docker install
if ! command -v docker >/dev/null 2>&1; then
  sudo apt-get update -qq
  sudo apt-get install -y -qq ca-certificates curl gnupg
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  sudo apt-get update -qq
  sudo apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi
sudo usermod -aG docker sentinel 2>/dev/null || true
sudo systemctl enable --now docker
echo "Docker: $(docker --version)"
echo "Compose: $(docker compose version)"

sudo mkdir -p /opt/sentinel/{media/movies,media/tv,data/pihole,data/pihole-dnsmasq,data/wgeasy,data/jellyfin,data/jellyfin-cache,data/nextcloud,data/open-webui,data/uptime-kuma,logs}
sudo chown -R sentinel:sentinel /opt/sentinel

if systemctl is-active systemd-resolved >/dev/null 2>&1; then
  sudo systemctl stop systemd-resolved
  sudo systemctl disable systemd-resolved
  sudo rm -f /etc/resolv.conf
  echo "nameserver 127.0.0.1" | sudo tee /etc/resolv.conf >/dev/null
fi

# Copy compose from install-services or write inline - assume already on disk from scp
if [ ! -f /opt/sentinel/docker-compose.yml ]; then
  echo "ERROR: docker-compose.yml missing"
  exit 1
fi

cd /opt/sentinel
sudo docker compose pull
sudo docker compose up -d
sleep 20
sudo docker ps

# wg-easy client
COOKIE_JAR="/tmp/wgeasy-cookie.txt"
curl -sf -c "$COOKIE_JAR" -X POST "http://localhost:51821/api/session" \
  -H "Content-Type: application/json" -d '{"password":"maddy123"}' || true
curl -sf -b "$COOKIE_JAR" -X POST "http://localhost:51821/api/wireguard/client" \
  -H "Content-Type: application/json" -d '{"name":"paul-laptop"}' || true

echo "DOCKER SERVICES UP"
