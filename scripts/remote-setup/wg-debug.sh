#!/bin/bash
curl -v -X POST http://localhost:51821/api/session \
  -H "Content-Type: application/json" \
  -d '{"password":"maddy123"}' 2>&1 | tail -20
echo "---"
curl -s http://localhost:51821/ | head -5
echo "---"
sudo docker exec sentinel-wgeasy ls -la /etc/wireguard/ 2>/dev/null
sudo docker exec sentinel-wgeasy cat /etc/wireguard/wg0.conf 2>/dev/null | head -20
