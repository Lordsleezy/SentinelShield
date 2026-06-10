#!/bin/bash
ps aux | grep -E 'node|npm|npx|medusa|create' | grep -v grep || echo "no install processes"
ls -la /opt/sentinel/medusa 2>/dev/null | head -15 || echo "medusa dir missing"
du -sh /opt/sentinel/medusa 2>/dev/null || true
systemctl is-active postgresql 2>/dev/null
sudo -u postgres psql -tc "SELECT datname FROM pg_database WHERE datname='sentinel_market';" 2>/dev/null
