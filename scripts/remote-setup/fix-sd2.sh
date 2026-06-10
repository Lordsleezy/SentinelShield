#!/bin/bash
set -euo pipefail
SD=/opt/sentinel/stablediffusion
cd "$SD"

cat > webui-user.sh << 'EOF'
#!/bin/bash
export COMMANDLINE_ARGS="--api --listen --port 7860 --skip-torch-cuda-test"
export TORCH_COMMAND="pip install torch==2.5.1 torchvision==0.20.1 --extra-index-url https://download.pytorch.org/whl/cu121"
EOF
chmod +x webui-user.sh

# Pre-install setuptools and torch before full webui install
if [ -d venv ]; then
  venv/bin/pip install --upgrade pip setuptools wheel
  venv/bin/pip install torch==2.5.1 torchvision==0.20.1 --extra-index-url https://download.pytorch.org/whl/cu121
fi

echo "Running webui install..."
bash webui.sh --exit 2>&1 | tee -a /opt/sentinel/logs/sd-install.log | tail -40

# Fix systemd to use Restart=always while loading
cat > /tmp/sentinel-stablediffusion.service << 'EOF'
[Unit]
Description=Sentinel Stable Diffusion WebUI (AUTOMATIC1111)
After=network.target

[Service]
Type=simple
User=sentinel
Group=sentinel
WorkingDirectory=/opt/sentinel/stablediffusion
ExecStart=/bin/bash /opt/sentinel/stablediffusion/webui.sh
Restart=on-failure
RestartSec=30
StandardOutput=append:/opt/sentinel/logs/stablediffusion.log
StandardError=append:/opt/sentinel/logs/stablediffusion.log

[Install]
WantedBy=multi-user.target
EOF
echo maddy123 | sudo -S cp /tmp/sentinel-stablediffusion.service /etc/systemd/system/
echo maddy123 | sudo -S systemctl daemon-reload
echo maddy123 | sudo -S systemctl enable sentinel-stablediffusion
echo maddy123 | sudo -S systemctl restart sentinel-stablediffusion

sleep 60
systemctl is-active sentinel-stablediffusion || true
curl -sf -o /dev/null -w "7860: %{http_code}\n" http://localhost:7860 || tail -15 /opt/sentinel/logs/stablediffusion.log
