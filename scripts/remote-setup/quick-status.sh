#!/usr/bin/env bash
sshpass -p maddy123 ssh -o StrictHostKeyChecking=no -o ConnectTimeout=15 sentinel@192.168.0.117 'docker ps -a --format "table {{.Names}}\t{{.Status}}" | head -10; echo ---; systemctl is-active sentinel-sd 2>/dev/null || echo sd-not-configured; test -d /opt/sentinel/stablediffusion && echo sd-dir-exists || echo sd-dir-missing'
