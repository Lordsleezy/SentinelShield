#!/bin/bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
LOG="/tmp/sentinel-setup.log"
exec > >(tee -a "$LOG") 2>&1

sudo() {
  if command sudo -n true 2>/dev/null; then
    command sudo "$@"
  else
    echo "${SUDO_PASS:-}" | command sudo -S "$@"
  fi
}

echo "=== SENTINEL SETUP START $(date) ==="

# --- INVENTORY ---
echo "=== GPU ==="
GPU_INFO=$(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null || echo "NO_GPU")
echo "$GPU_INFO"

VRAM_MB=0
if echo "$GPU_INFO" | grep -qi "MiB"; then
  VRAM_MB=$(echo "$GPU_INFO" | grep -oE '[0-9]+ MiB' | head -1 | grep -oE '[0-9]+')
elif echo "$GPU_INFO" | grep -qi "GiB"; then
  VRAM_GB=$(echo "$GPU_INFO" | grep -oE '[0-9]+' | head -1)
  VRAM_MB=$((VRAM_GB * 1024))
fi
echo "Detected VRAM_MB: $VRAM_MB"

echo "=== RAM ==="
free -h | grep Mem

echo "=== CPU ==="
nproc
lscpu | grep "Model name" || true

echo "=== DISK BEFORE ==="
df -h /

# --- SYSTEM PACKAGES ---
echo "=== APT UPDATE & BASE PACKAGES ==="
sudo apt-get update -qq
sudo apt-get install -y -qq git curl wget screen htop build-essential software-properties-common

# pip via apt (python3-pip)
if ! command -v pip3 >/dev/null 2>&1; then
  sudo apt-get install -y -qq python3-pip
fi

# --- PYTHON 3.11+ via deadsnakes ---
PY_VER=$(python3 --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' || echo "0")
PY_MAJOR=$(echo "$PY_VER" | cut -d. -f1)
PY_MINOR=$(echo "$PY_VER" | cut -d. -f2)
PYTHON_BIN="python3"

if [ "$PY_MAJOR" -lt 3 ] || { [ "$PY_MAJOR" -eq 3 ] && [ "$PY_MINOR" -lt 11 ]; }; then
  echo "Installing Python 3.11 via deadsnakes..."
  sudo add-apt-repository -y ppa:deadsnakes/ppa
  sudo apt-get update -qq
  sudo apt-get install -y -qq python3.11 python3.11-venv python3.11-dev
  PYTHON_BIN="python3.11"
fi
echo "Using Python: $($PYTHON_BIN --version)"

# --- NODE via NVM ---
if ! command -v node >/dev/null 2>&1 || [ "$(node -v | grep -oE '[0-9]+' | head -1)" -lt 20 ]; then
  echo "Installing Node.js 20 via nvm..."
  export NVM_DIR="$HOME/.nvm"
  if [ ! -d "$NVM_DIR" ]; then
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
  fi
  # shellcheck source=/dev/null
  [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
  nvm install 20
  nvm alias default 20
  nvm use default
fi
# Ensure nvm is in bashrc
if ! grep -q 'NVM_DIR' "$HOME/.bashrc" 2>/dev/null; then
  cat >> "$HOME/.bashrc" << 'NVMEOF'

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
NVMEOF
fi

# --- OLLAMA ---
if ! command -v ollama >/dev/null 2>&1; then
  echo "Installing Ollama..."
  curl -fsSL https://ollama.com/install.sh | sh
else
  echo "Ollama already installed"
fi

sudo systemctl enable ollama
sudo systemctl start ollama
sleep 3

# Pull models based on VRAM (RTX 2070 = 8GB, be safe with 6GB threshold)
if [ "$VRAM_MB" -ge 7500 ]; then
  echo "VRAM >= 7.5GB: pulling mistral and phi3:mini"
  ollama pull mistral
  ollama pull phi3:mini
elif [ "$VRAM_MB" -ge 5500 ]; then
  echo "VRAM ~6-8GB (safe mode): pulling phi3:mini and tinyllama"
  ollama pull phi3:mini
  ollama pull tinyllama
else
  echo "Low VRAM or no GPU: pulling phi3:mini and tinyllama"
  ollama pull phi3:mini
  ollama pull tinyllama
fi

# --- PYTHON PACKAGES ---
echo "=== PYTHON PACKAGES ==="
PIP="$PYTHON_BIN -m pip"
$PIP install --user --upgrade pip
$PIP install --user playwright playwright-stealth crawl4ai python-dotenv requests ollama serper 2>/dev/null || \
  $PIP install --user playwright playwright-stealth crawl4ai python-dotenv requests ollama

# Playwright browsers
$PYTHON_BIN -m playwright install chromium
$PYTHON_BIN -m playwright install-deps chromium 2>/dev/null || sudo $PYTHON_BIN -m playwright install-deps chromium

# --- CLOUDFLARED ---
if ! command -v cloudflared >/dev/null 2>&1; then
  echo "Installing cloudflared..."
  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64) CF_ARCH="amd64" ;;
    aarch64|arm64) CF_ARCH="arm64" ;;
    *) CF_ARCH="amd64" ;;
  esac
  curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CF_ARCH}.deb" -o /tmp/cloudflared.deb
  sudo dpkg -i /tmp/cloudflared.deb
  rm -f /tmp/cloudflared.deb
else
  echo "cloudflared already installed"
fi

# --- DIRECTORY STRUCTURE ---
echo "=== CREATING DIRECTORIES ==="
sudo mkdir -p /opt/sentinel/scout /opt/sentinel/lister /opt/sentinel/logs
sudo chown -R sentinel:sentinel /opt/sentinel

# --- SCOUT SCAFFOLD ---
cat > /opt/sentinel/scout/main.py << 'SCOUTEOF'
#!/usr/bin/env python3
"""
Scout — Legion product search and deal scoring service.

Flow:
  1. Accept a natural language product search query (CLI arg or stdin).
  2. Call the Serper Google Shopping API to fetch candidate products.
  3. Pass results to Ollama for deal scoring and ranking.
  4. Return ranked results (JSON) to stdout or caller.

Environment variables (see .env.example):
  SERPER_API_KEY, OLLAMA_HOST, MEDUSA_API_URL, MEDUSA_API_KEY
"""

import sys
import time


def main() -> None:
    if len(sys.argv) >= 2 and sys.argv[1] == "--service":
        print("[stub] Scout service running (waiting for implementation)")
        while True:
            time.sleep(60)
        return
    if len(sys.argv) < 2:
        print("Usage: python main.py <search query>", file=sys.stderr)
        print("       python main.py --service", file=sys.stderr)
        sys.exit(1)
    query = " ".join(sys.argv[1:])
    # TODO: Serper API lookup → Ollama deal scoring → ranked output
    print(f"[stub] Scout received query: {query!r}")


if __name__ == "__main__":
    main()
SCOUTEOF

cat > /opt/sentinel/scout/requirements.txt << 'EOF'
playwright
playwright-stealth
python-dotenv
requests
ollama
EOF

cat > /opt/sentinel/scout/.env.example << 'EOF'
SERPER_API_KEY=
OLLAMA_HOST=http://localhost:11434
MEDUSA_API_URL=
MEDUSA_API_KEY=
EOF

cat > /opt/sentinel/scout/README.md << 'EOF'
# Scout

Scout is the Legion product search and deal-scoring service.

## What it does

1. Accepts a natural language product search query.
2. Queries the **Serper Google Shopping API** for candidate listings.
3. Sends results to **Ollama** for deal scoring and ranking.
4. Returns ranked results as JSON.

## Setup

```bash
cd /opt/sentinel/scout
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
cp .env.example .env   # fill in SERPER_API_KEY, etc.
```

## Run

```bash
python main.py "wireless earbuds under $50"
```

## Service

```bash
sudo systemctl start sentinel-scout
sudo systemctl status sentinel-scout
```
EOF

# --- LISTER SCAFFOLD ---
cat > /opt/sentinel/lister/main.py << 'LISTEREOF'
#!/usr/bin/env python3
"""
Lister — Legion product listing generator.

Flow:
  1. Accept a product URL or product name (CLI arg).
  2. Use Crawl4AI to extract full product data from the source page.
  3. Pass extracted data to Ollama to generate a clean listing
     (title, description, specs).
  4. Push the listing to Medusa via API.

Environment variables (see .env.example):
  OLLAMA_HOST, MEDUSA_API_URL, MEDUSA_API_KEY, SERPER_API_KEY
"""

import sys
import time


def main() -> None:
    if len(sys.argv) >= 2 and sys.argv[1] == "--service":
        print("[stub] Lister service running (waiting for implementation)")
        while True:
            time.sleep(60)
        return
    if len(sys.argv) < 2:
        print("Usage: python main.py <product URL or name>", file=sys.stderr)
        print("       python main.py --service", file=sys.stderr)
        sys.exit(1)
    target = " ".join(sys.argv[1:])
    # TODO: Crawl4AI extract → Ollama listing generation → Medusa API push
    print(f"[stub] Lister received target: {target!r}")


if __name__ == "__main__":
    main()
LISTEREOF

cat > /opt/sentinel/lister/requirements.txt << 'EOF'
crawl4ai
python-dotenv
requests
ollama
EOF

cat > /opt/sentinel/lister/.env.example << 'EOF'
OLLAMA_HOST=http://localhost:11434
MEDUSA_API_URL=
MEDUSA_API_KEY=
SERPER_API_KEY=
EOF

cat > /opt/sentinel/lister/README.md << 'EOF'
# Lister

Lister is the Legion product listing generator.

## What it does

1. Accepts a product URL or product name.
2. Uses **Crawl4AI** to extract full product data from the source.
3. Sends data to **Ollama** to generate a clean listing (title, description, specs).
4. Pushes the listing to **Medusa** via API.

## Setup

```bash
cd /opt/sentinel/lister
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
cp .env.example .env   # fill in MEDUSA_API_URL, MEDUSA_API_KEY, etc.
```

## Run

```bash
python main.py "https://example.com/product/123"
```

## Service

```bash
sudo systemctl start sentinel-lister
sudo systemctl status sentinel-lister
```
EOF

chmod +x /opt/sentinel/scout/main.py /opt/sentinel/lister/main.py

# --- SYSTEMD SERVICES ---
echo "=== SYSTEMD SERVICES ==="

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
ExecStart=/usr/bin/python3 /opt/sentinel/scout/main.py --service
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
ExecStart=/usr/bin/python3 /opt/sentinel/lister/main.py --service
Restart=on-failure
RestartSec=10
StandardOutput=append:/opt/sentinel/logs/lister.log
StandardError=append:/opt/sentinel/logs/lister.log

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable sentinel-scout sentinel-lister ollama
sudo systemctl start sentinel-scout sentinel-lister

# --- FINAL REPORT ---
echo ""
echo "========================================"
echo "       SENTINEL SETUP FINAL REPORT"
echo "========================================"
echo ""
echo "--- GPU ---"
nvidia-smi 2>/dev/null || echo "No NVIDIA GPU detected"
echo ""
echo "--- Versions ---"
for cmd in node npm python3 python3.11 pip3 git curl wget screen htop ollama cloudflared; do
  if command -v "$cmd" >/dev/null 2>&1; then
    echo "  $cmd: $($cmd --version 2>&1 | head -1)"
  fi
done
# nvm node
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
command -v node >/dev/null && echo "  node (nvm): $(node -v)"
command -v npm >/dev/null && echo "  npm (nvm): $(npm -v)"

echo ""
echo "--- Ollama ---"
systemctl is-enabled ollama 2>/dev/null && echo "  ollama service: enabled"
systemctl is-active ollama 2>/dev/null && echo "  ollama service: active"
ollama list 2>/dev/null || true

echo ""
echo "--- Disk & RAM ---"
df -h /
free -h | grep Mem

echo ""
echo "--- Directories & Files ---"
find /opt/sentinel -type f -o -type d | sort

echo ""
echo "--- Systemd Services ---"
systemctl list-unit-files | grep sentinel || true

echo ""
echo "--- Manual Intervention Required ---"
echo "  1. Cloudflare Tunnel: run 'cloudflared tunnel login' to authenticate (not done automatically)"
echo "  2. API keys: copy .env.example to .env in scout/ and lister/, fill SERPER_API_KEY, MEDUSA_API_URL, MEDUSA_API_KEY"
echo "  3. Scout/Lister stubs: implement real logic; --service mode runs idle loop for now"
echo "  4. Optional: create venvs in scout/ and lister/ and point systemd ExecStart at venv python"

echo ""
echo "=== SETUP COMPLETE $(date) ==="
