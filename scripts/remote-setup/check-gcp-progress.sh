#!/usr/bin/env bash
sshpass -p maddy123 ssh -o StrictHostKeyChecking=no pgg124@136.118.148.167 'bash -s' <<'REMOTE'
echo "=== Install log tail ==="
tail -20 /tmp/gcp-nosudo3.log 2>/dev/null || echo no-log
echo ""
echo "=== Processes ==="
pgrep -af "create-medusa|medusa|npm" 2>/dev/null | head -8 || echo none
echo ""
echo "=== Dirs ==="
ls -la ~/medusa-build 2>/dev/null | head -5 || echo no-build-dir
ls -la /opt/medusa 2>/dev/null | head -8 || echo no-opt-medusa
echo ""
echo "=== Services ==="
systemctl is-active postgresql redis-server 2>/dev/null
systemctl --user is-active sentinel-medusa 2>/dev/null || echo medusa-user-svc-inactive
curl -s -o /dev/null -w "health:%{http_code}\n" http://localhost:9000/health 2>/dev/null || echo health-unreachable
echo ""
echo "=== Disk ==="
df -h / | tail -1
du -sh ~/medusa-build /opt/medusa 2>/dev/null
REMOTE
