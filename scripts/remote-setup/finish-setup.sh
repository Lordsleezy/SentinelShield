#!/bin/bash
set -euo pipefail

sudo() {
  if command sudo -n true 2>/dev/null; then
    command sudo "$@"
  else
    echo "${SUDO_PASS:-}" | command sudo -S "$@"
  fi
}

PYTHON_BIN="python3"
echo "=== FINISH SETUP $(date) ==="

# --- DIRECTORIES ---
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
playwright install chromium
```

## Run

```bash
source venv/bin/activate
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
source venv/bin/activate
python main.py "https://example.com/product/123"
```

## Service

```bash
sudo systemctl start sentinel-lister
sudo systemctl status sentinel-lister
```
EOF

chmod +x /opt/sentinel/scout/main.py /opt/sentinel/lister/main.py

# --- VENVS & PYTHON PACKAGES ---
echo "=== Creating venvs and installing Python packages ==="
sudo apt-get install -y -qq python3-venv python3-full 2>/dev/null || true

$PYTHON_BIN -m venv /opt/sentinel/scout/venv
/opt/sentinel/scout/venv/bin/pip install --upgrade pip
/opt/sentinel/scout/venv/bin/pip install -r /opt/sentinel/scout/requirements.txt
/opt/sentinel/scout/venv/bin/playwright install chromium
/opt/sentinel/scout/venv/bin/playwright install-deps chromium 2>/dev/null || \
  sudo /opt/sentinel/scout/venv/bin/playwright install-deps chromium

$PYTHON_BIN -m venv /opt/sentinel/lister/venv
/opt/sentinel/lister/venv/bin/pip install --upgrade pip
/opt/sentinel/lister/venv/bin/pip install -r /opt/sentinel/lister/requirements.txt

# --- SYSTEMD ---
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
sudo systemctl start sentinel-scout sentinel-lister

# --- FINAL REPORT ---
echo ""
echo "========================================"
echo "       SENTINEL SETUP FINAL REPORT"
echo "========================================"

echo ""
echo "--- GPU & VRAM ---"
nvidia-smi --query-gpu=name,memory.total,memory.used,memory.free --format=csv 2>/dev/null || echo "No GPU"
nvidia-smi 2>/dev/null | tail -5 || true

echo ""
echo "--- Installed Versions ---"
for cmd in node npm python3 pip3 git curl wget screen htop ollama cloudflared; do
  if command -v "$cmd" >/dev/null 2>&1; then
    echo "  $cmd: $($cmd --version 2>&1 | head -1)"
  fi
done
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
command -v node >/dev/null && echo "  node (nvm): $(node -v)"
command -v npm >/dev/null && echo "  npm (nvm): $(npm -v)"
echo "  scout venv pip: $(/opt/sentinel/scout/venv/bin/pip --version)"
echo "  lister venv pip: $(/opt/sentinel/lister/venv/bin/pip --version)"

echo ""
echo "--- Ollama Models ---"
ollama list 2>/dev/null || true
echo "Ollama service: $(systemctl is-enabled ollama 2>/dev/null) / $(systemctl is-active ollama 2>/dev/null)"

echo ""
echo "--- Scout/Lister Services ---"
systemctl is-enabled sentinel-scout sentinel-lister 2>/dev/null || true
systemctl is-active sentinel-scout sentinel-lister 2>/dev/null || true

echo ""
echo "--- Disk & RAM Usage ---"
df -h /
free -h | grep Mem

echo ""
echo "--- Files Created ---"
find /opt/sentinel | sort

echo ""
echo "--- Manual Intervention ---"
echo "  1. Cloudflare: run 'cloudflared tunnel login' (not authenticated)"
echo "  2. API keys: cp scout/.env.example scout/.env and lister/.env.example lister/.env"
echo "  3. Pre-existing llama3 model still on disk (4.7GB) — consider 'ollama rm llama3' to free space"
echo "  4. Fill SERPER_API_KEY, MEDUSA_API_URL, MEDUSA_API_KEY in .env files"

echo ""
echo "=== FINISH COMPLETE $(date) ==="
