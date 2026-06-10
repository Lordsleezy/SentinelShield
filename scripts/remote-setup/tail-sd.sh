#!/bin/bash
tail -15 /tmp/fix-sd2.log 2>/dev/null
echo "---"
systemctl is-active sentinel-stablediffusion 2>/dev/null
curl -sf -o /dev/null -w "7860: %{http_code}\n" http://localhost:7860 2>/dev/null || echo "7860: down"
pgrep -af fix-sd2 || pgrep -af webui || echo "no install proc"
