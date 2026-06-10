#!/bin/bash
SUDO_PASS="${SUDO_PASS:-maddy123}"
sudo() { echo "$SUDO_PASS" | command sudo -S "$@"; }

sudo chattr -i /etc/resolv.conf 2>/dev/null || true
printf "nameserver 8.8.8.8\nnameserver 1.1.1.1\n" > /tmp/resolv.conf
sudo cp /tmp/resolv.conf /etc/resolv.conf

cat > /tmp/daemon.json << 'EOF'
{
  "dns": ["8.8.8.8", "1.1.1.1"],
  "ipv6": false
}
EOF
sudo mkdir -p /etc/docker
sudo cp /tmp/daemon.json /etc/docker/daemon.json

# Stop anything hijacking port 53 locally
sudo docker stop sentinel-pihole 2>/dev/null || true

sudo systemctl restart docker
sleep 5

echo "=== resolv.conf ==="
cat /etc/resolv.conf
echo "=== port 53 ==="
sudo ss -tulpn | grep ':53' || echo "nothing on 53"
echo "=== ping DNS ==="
ping -c1 -W2 8.8.8.8 >/dev/null && echo "8.8.8.8 ok" || echo "8.8.8.8 fail"
getent hosts registry-1.docker.io || nslookup registry-1.docker.io 8.8.8.8 2>&1 | tail -3

echo "=== docker pull test ==="
sudo docker pull hello-world 2>&1 | tail -5

if sudo docker images | grep -q hello-world; then
  echo "=== pulling compose images ==="
  cd /opt/sentinel
  sudo docker compose pull 2>&1 | tail -25
  sudo docker compose up -d 2>&1
  sleep 15
  sudo docker ps
fi
