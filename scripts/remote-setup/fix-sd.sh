#!/bin/bash
set -euo pipefail
SUDO_PASS="${SUDO_PASS:-maddy123}"
sudo() { echo "$SUDO_PASS" | command sudo -S "$@"; }

SD=/opt/sentinel/stablediffusion
cd "$SD"

# Override torch version for Python 3.12
cat > webui-user.sh << 'EOF'
#!/bin/bash
export COMMANDLINE_ARGS="--api --listen --port 7860 --skip-torch-cuda-test"
export TORCH_COMMAND="pip install torch==2.5.1 torchvision==0.20.1 --extra-index-url https://download.pytorch.org/whl/cu121"
export CUDA_HOME=/usr/local/cuda
EOF
chmod +x webui-user.sh

log() { echo "[SD-FIX] $*"; tee -a /opt/sentinel/logs/sd-install.log; }
log "Installing deps with compatible torch..."
bash webui.sh --exit 2>&1 | tail -30 | tee -a /opt/sentinel/logs/sd-install.log

sudo systemctl restart sentinel-stablediffusion
log "Service: $(systemctl is-active sentinel-stablediffusion)"
sleep 30
curl -sf -o /dev/null -w "7860: %{http_code}\n" http://localhost:7860 || tail -10 /opt/sentinel/logs/stablediffusion.log
