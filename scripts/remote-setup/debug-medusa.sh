#!/bin/bash
systemctl status sentinel-medusa --no-pager -l 2>&1 | head -30
echo "=== LOG ==="
tail -50 /opt/sentinel/logs/medusa.log 2>/dev/null || journalctl -u sentinel-medusa -n 50 --no-pager
echo "=== ENV PORT ==="
grep PORT /opt/sentinel/medusa/apps/backend/.env 2>/dev/null || echo "no PORT"
echo "=== Manual start test ==="
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
cd /opt/sentinel/medusa/apps/backend
timeout 15 npx medusa start 2>&1 | head -30 || true
