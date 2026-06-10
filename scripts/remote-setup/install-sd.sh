#!/bin/bash
set -euo pipefail
SUDO_PASS="${SUDO_PASS:-maddy123}"
sudo() { echo "$SUDO_PASS" | command sudo -S "$@"; }
log() { echo "[SD $(date +%H:%M:%S)] $*"; tee -a /opt/sentinel/logs/sd-install.log; }

SD_DIR="/opt/sentinel/stablediffusion"
mkdir -p /opt/sentinel/logs

if [ ! -f "$SD_DIR/webui.sh" ]; then
  log "Cloning AUTOMATIC1111..."
  git clone https://github.com/AUTOMATIC1111/stable-diffusion-webui.git "$SD_DIR"
fi
cd "$SD_DIR"
mkdir -p models/Stable-diffusion

if [ ! -f models/Stable-diffusion/v1-5-pruned-emaonly.safetensors ]; then
  log "Downloading v1-5 model..."
  wget -c -O models/Stable-diffusion/v1-5-pruned-emaonly.safetensors \
    "https://huggingface.co/runwayml/stable-diffusion-v1-5/resolve/main/v1-5-pruned-emaonly.safetensors"
fi

log "Running webui.sh --exit to install deps..."
export COMMANDLINE_ARGS="--api --listen --port 7860 --skip-torch-cuda-test"
bash webui.sh --exit 2>&1 | tail -30 | tee -a /opt/sentinel/logs/sd-install.log

cat > /tmp/sentinel-stablediffusion.service << 'EOF'
[Unit]
Description=Sentinel Stable Diffusion WebUI (AUTOMATIC1111)
After=network.target

[Service]
Type=simple
User=sentinel
Group=sentinel
WorkingDirectory=/opt/sentinel/stablediffusion
Environment=COMMANDLINE_ARGS=--api --listen --port 7860 --skip-torch-cuda-test
ExecStart=/bin/bash /opt/sentinel/stablediffusion/webui.sh
Restart=on-failure
RestartSec=20
StandardOutput=append:/opt/sentinel/logs/stablediffusion.log
StandardError=append:/opt/sentinel/logs/stablediffusion.log

[Install]
WantedBy=multi-user.target
EOF
sudo cp /tmp/sentinel-stablediffusion.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable sentinel-stablediffusion
sudo systemctl restart sentinel-stablediffusion
log "SD service: $(systemctl is-active sentinel-stablediffusion)"
log "SD install complete"
