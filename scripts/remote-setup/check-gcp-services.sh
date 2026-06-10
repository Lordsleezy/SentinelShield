#!/usr/bin/env bash
sshpass -p maddy123 ssh -o StrictHostKeyChecking=no pgg124@136.118.148.167 'bash -s' <<'REMOTE'
echo "postgres: $(systemctl is-active postgresql 2>/dev/null)"
echo "redis: $(systemctl is-active redis-server 2>/dev/null)"
psql "postgresql://sentinel:maddy123@localhost:5432/sentinel_market" -c "SELECT 1" 2>&1
redis-cli ping 2>&1
node -v 2>/dev/null || echo no-node
REMOTE
