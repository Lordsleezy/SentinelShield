#!/bin/bash
# Phase 1: Docker + compose + wg + uptime kuma (no Stable Diffusion)
set -euo pipefail
SUDO_PASS="${SUDO_PASS:-maddy123}"
REPORT="/tmp/sentinel-services-report.txt"
sudo() { echo "$SUDO_PASS" | command sudo -S "$@"; }
log() { echo ">>> $*"; tee -a "$REPORT"; }
: > "$REPORT"

# [Include docker install + compose from install-services.sh - run via sourcing or inline]
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Execute lines 13-220 of install-services excluding SD section
bash -c '
set -euo pipefail
SUDO_PASS="${SUDO_PASS:-maddy123}"
REPORT="/tmp/sentinel-services-report.txt"
sudo() { echo "$SUDO_PASS" | command sudo -S "$@"; }
log() { echo ">>> $*"; tee -a "$REPORT"; }

if ! command -v docker >/dev/null 2>&1; then
  log "Installing Docker..."
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
log "Docker: $(docker --version)"
log "Compose: $(docker compose version)"

sudo mkdir -p /opt/sentinel/{media/movies,media/tv,data/pihole,data/pihole-dnsmasq,data/wgeasy,data/jellyfin,data/jellyfin-cache,data/nextcloud,data/open-webui,data/uptime-kuma,logs,scripts}
sudo chown -R sentinel:sentinel /opt/sentinel

if systemctl is-active systemd-resolved >/dev/null 2>&1; then
  log "Disabling systemd-resolved"
  sudo systemctl stop systemd-resolved
  sudo systemctl disable systemd-resolved
  sudo rm -f /etc/resolv.conf
  echo "nameserver 127.0.0.1" | sudo tee /etc/resolv.conf >/dev/null
fi
'

# Write compose file (rest of install-services content)
grep -A 999 'DOCKER COMPOSE' /tmp/remote_script.sh 2>/dev/null || true
