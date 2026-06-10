#!/bin/bash
set -euo pipefail

sudo() {
  if command sudo -n true 2>/dev/null; then
    command sudo "$@"
  else
    echo "${SUDO_PASS:-}" | command sudo -S "$@"
  fi
}

echo "=== PIP INSTALL & SERVICES $(date) ==="

# Scout venv (may already exist)
if [ ! -d /opt/sentinel/scout/venv ]; then
  python3 -m venv /opt/sentinel/scout/venv
fi
/opt/sentinel/scout/venv/bin/pip install --upgrade pip
/opt/sentinel/scout/venv/bin/pip install -r /opt/sentinel/scout/requirements.txt
/opt/sentinel/scout/venv/bin/playwright install chromium
/opt/sentinel/scout/venv/bin/playwright install-deps chromium 2>/dev/null || \
  sudo /opt/sentinel/scout/venv/bin/playwright install-deps chromium

# Lister venv
if [ ! -d /opt/sentinel/lister/venv ]; then
  python3 -m venv /opt/sentinel/lister/venv
fi
/opt/sentinel/lister/venv/bin/pip install --upgrade pip
/opt/sentinel/lister/venv/bin/pip install -r /opt/sentinel/lister/requirements.txt

# Systemd (idempotent)
sudo tee /etc/systemd/system/sentinel-scout.service > /dev/null << 'EOF'
[Unit]
Description=Sentinel Scout - Product search and deal scoring
After=network.target ollama.service
Wants=ollama.service

[Service]
Type=simple
User=sentinel
Group=sentinel
WorkingDirectory=/opt/sentinel/scout
EnvironmentFile=-/opt/sentinel/scout/.env
ExecStart=/opt/sentinel/scout/venv/bin/python /opt/sentinel/scout/main.py --service
Restart=on-failure
RestartSec=10
StandardOutput=append:/opt/sentinel/logs/scout.log
StandardError=append:/opt/sentinel/logs/scout.log

[Install]
WantedBy=multi-user.target
EOF

sudo tee /etc/systemd/system/sentinel-lister.service > /dev/null << 'EOF'
[Unit]
Description=Sentinel Lister - Product listing generator
After=network.target ollama.service
Wants=ollama.service

[Service]
Type=simple
User=sentinel
Group=sentinel
WorkingDirectory=/opt/sentinel/lister
EnvironmentFile=-/opt/sentinel/lister/.env
ExecStart=/opt/sentinel/lister/venv/bin/python /opt/sentinel/lister/main.py --service
Restart=on-failure
RestartSec=10
StandardOutput=append:/opt/sentinel/logs/lister.log
StandardError=append:/opt/sentinel/logs/lister.log

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable ollama sentinel-scout sentinel-lister
sudo systemctl restart sentinel-scout sentinel-lister

echo "=== FINAL REPORT ==="
echo "--- GPU ---"
nvidia-smi --query-gpu=name,memory.total,memory.used,memory.free --format=csv 2>/dev/null
echo ""
echo "--- Versions ---"
for cmd in node npm python3 pip3 git curl wget screen htop ollama cloudflared; do
  command -v "$cmd" >/dev/null 2>&1 && echo "  $cmd: $($cmd --version 2>&1 | head -1)"
done
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
command -v node >/dev/null && echo "  node: $(node -v)"
command -v npm >/dev/null && echo "  npm: $(npm -v)"
echo "  scout packages: $(/opt/sentinel/scout/venv/bin/pip list --format=freeze | wc -l) installed"
echo "  lister packages: $(/opt/sentinel/lister/venv/bin/pip list --format=freeze | wc -l) installed"
/opt/sentinel/scout/venv/bin/pip show playwright playwright-stealth crawl4ai ollama 2>/dev/null | grep -E '^Name:|^Version:' || true
/opt/sentinel/lister/venv/bin/pip show crawl4ai ollama 2>/dev/null | grep -E '^Name:|^Version:' || true

echo ""
echo "--- Ollama ---"
systemctl is-enabled ollama; systemctl is-active ollama
ollama list

echo ""
echo "--- Services ---"
systemctl is-enabled sentinel-scout sentinel-lister
systemctl is-active sentinel-scout sentinel-lister

echo ""
echo "--- Disk & RAM ---"
df -h /
free -h | grep Mem

echo ""
echo "--- Files ---"
find /opt/sentinel | sort

echo ""
echo "--- Manual ---"
echo "  cloudflared tunnel login (not done)"
echo "  cp .env.example to .env in scout/ and lister/"
echo "  consider: ollama rm llama3 (4.7GB, not recommended for 8GB VRAM)"

echo "=== DONE ==="
