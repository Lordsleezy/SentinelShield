#!/usr/bin/env bash
sshpass -p maddy123 ssh -o StrictHostKeyChecking=no pgg124@136.118.148.167 'bash -s' <<'REMOTE'
echo "=== sudo test ==="
echo maddy123 | sudo -S id 2>&1
echo "=== sudo -l ==="
sudo -l 2>&1
echo "=== which cloudflared ==="
which cloudflared 2>/dev/null || ls /usr/local/bin/cloudflared 2>/dev/null || echo none
echo "=== docker ==="
docker ps 2>&1 | head -3
REMOTE
