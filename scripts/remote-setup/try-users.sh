#!/bin/bash
PASS="maddy123"
HOST="192.168.0.117"
for user in pgg12 maddy ubuntu admin root; do
  echo "Trying user: $user"
  if sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "${user}@${HOST}" 'whoami' 2>/dev/null; then
    echo "SUCCESS: $user"
    exit 0
  fi
done
echo "FAILED: no user worked"
exit 1
