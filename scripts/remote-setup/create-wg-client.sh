#!/bin/bash
COOKIE="/tmp/wgeasy-cookie.txt"
curl -sf -c "$COOKIE" -X POST "http://localhost:51821/api/session" \
  -H "Content-Type: application/json" -d '{"password":"maddy123"}'
echo ""
RESP=$(curl -sf -b "$COOKIE" -X POST "http://localhost:51821/api/wireguard/client" \
  -H "Content-Type: application/json" -d '{"name":"paul-laptop"}')
echo "Create: $RESP"
# Get client config
CLIENTS=$(curl -sf -b "$COOKIE" "http://localhost:51821/api/wireguard/client")
echo "$CLIENTS" | python3 -c "
import sys,json
d=json.load(sys.stdin)
items=d if isinstance(d,list) else d.get('clients',d)
for c in (items if isinstance(items,list) else []):
    if c.get('name')=='paul-laptop':
        print('Found paul-laptop id:', c.get('id','?'))
" 2>/dev/null

# Download config file if API supports it
ID=$(echo "$CLIENTS" | python3 -c "
import sys,json
d=json.load(sys.stdin)
items=d if isinstance(d,list) else []
for c in items:
    if c.get('name')=='paul-laptop':
        print(c.get('id','')); break
" 2>/dev/null)
if [ -n "$ID" ]; then
  curl -sf -b "$COOKIE" "http://localhost:51821/api/wireguard/client/$ID/configuration" \
    -o /opt/sentinel/data/wgeasy/clients/paul-laptop.conf 2>/dev/null && \
    echo "Saved: /opt/sentinel/data/wgeasy/clients/paul-laptop.conf" && \
    head -5 /opt/sentinel/data/wgeasy/clients/paul-laptop.conf
fi
