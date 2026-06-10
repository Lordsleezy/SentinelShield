#!/bin/bash
echo "=== DOCKER ==="
docker --version 2>/dev/null || echo "no docker"
docker ps 2>/dev/null || sudo docker ps 2>/dev/null
echo "=== PROCESSES ==="
ps aux | grep -E 'apt|docker|install-sd|webui|wget' | grep -v grep | head -15
echo "=== SD LOG ==="
tail -10 /opt/sentinel/logs/sd-install.log 2>/dev/null || echo "no sd log"
echo "=== COMPOSE ==="
ls -la /opt/sentinel/docker-compose.yml 2>/dev/null
echo "=== SD SERVICE ==="
systemctl is-active sentinel-stablediffusion 2>/dev/null || echo inactive
echo "=== DISK ==="
df -h / | tail -1
free -h | grep Mem
