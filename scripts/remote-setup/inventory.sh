#!/bin/bash
set -euo pipefail

echo "=== GPU ==="
nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null || echo "NO_GPU"

echo "=== RAM ==="
free -h | grep Mem

echo "=== CPU ==="
nproc
lscpu | grep "Model name" || true

echo "=== DISK ==="
df -h / /home 2>/dev/null || df -h /

echo "=== INSTALLED ==="
for cmd in node npm python3 python pip3 pip git curl wget screen htop ollama cloudflared; do
  if command -v "$cmd" >/dev/null 2>&1; then
    echo "$cmd: $($cmd --version 2>&1 | head -1)"
  else
    echo "$cmd: NOT INSTALLED"
  fi
done

echo "=== OLLAMA STATUS ==="
systemctl is-active ollama 2>/dev/null || echo "inactive"
ollama list 2>/dev/null || echo "no_ollama"
