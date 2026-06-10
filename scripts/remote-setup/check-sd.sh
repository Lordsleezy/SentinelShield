#!/bin/bash
systemctl status sentinel-stablediffusion --no-pager -l 2>&1 | head -15
tail -20 /opt/sentinel/logs/stablediffusion.log 2>/dev/null
curl -sf -o /dev/null -w "7860: %{http_code}\n" http://localhost:7860 2>/dev/null || echo "7860: starting"
